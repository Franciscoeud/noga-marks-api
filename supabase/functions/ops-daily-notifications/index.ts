// Supabase Edge Function: ops-daily-notifications
// Sends or dry-runs OPS WhatsApp daily summaries through Twilio.

import { serve } from "https://deno.land/std@0.203.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.7";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const TWILIO_ACCOUNT_SID = Deno.env.get("TWILIO_ACCOUNT_SID") ?? "";
const TWILIO_AUTH_TOKEN = Deno.env.get("TWILIO_AUTH_TOKEN") ?? "";
const TWILIO_WHATSAPP_FROM = Deno.env.get("TWILIO_WHATSAPP_FROM") ?? "";
const TWILIO_OPS_DAILY_CONTENT_SID = Deno.env.get("TWILIO_OPS_DAILY_CONTENT_SID") ?? "";
const TWILIO_OPS_ASSIGNEE_CONTENT_SID = Deno.env.get("TWILIO_OPS_ASSIGNEE_CONTENT_SID") ?? "";
const OPS_APP_BASE_URL = (Deno.env.get("OPS_APP_BASE_URL") ?? "https://planner.nogamarks.com").replace(/\/+$/, "");
const OPS_NOTIFICATION_SECRET = Deno.env.get("OPS_NOTIFICATION_SECRET") ?? "";
const TWILIO_ALLOW_FREEFORM_BODY = Deno.env.get("TWILIO_ALLOW_FREEFORM_BODY") === "true";
const OPS_NOTIFICATION_ALLOW_USER_SEND = Deno.env.get("OPS_NOTIFICATION_ALLOW_USER_SEND") === "true";

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-ops-notification-secret",
};

const SPANISH_WEEKDAYS = [
  "domingo",
  "lunes",
  "martes",
  "miércoles",
  "jueves",
  "viernes",
  "sábado",
];

const SPANISH_SHORT_MONTHS = [
  "ene",
  "feb",
  "mar",
  "abr",
  "may",
  "jun",
  "jul",
  "ago",
  "sep",
  "oct",
  "nov",
  "dic",
];

type NotificationMode = "daily" | "assignees" | "all";

type NotificationRequest = {
  mode?: NotificationMode;
  dry_run?: boolean;
  force?: boolean;
  notification_date?: string;
  limit?: number;
  recipient_ids?: string[];
  recipient_id?: string;
  assignee_id?: string;
};

type NotificationRecipient = {
  id: string;
  name: string;
  whatsapp_to: string;
  recipient_type: "general" | "assignee";
  assignee_id: string | null;
  active: boolean;
  timezone: string;
};

type SendResult = {
  recipient_id: string;
  recipient_name: string;
  notification_type: "daily_summary" | "assignee_summary";
  status: "success" | "error" | "skipped";
  dry_run: boolean;
  twilio_message_sid?: string | null;
  error_message?: string | null;
  preview?: string;
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body, null, 2), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function getBearerToken(req: Request) {
  const authorization = req.headers.get("authorization") ?? "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  return match?.[1] ?? "";
}

function isServiceRoleRequest(req: Request) {
  return getBearerToken(req) === SUPABASE_SERVICE_ROLE_KEY;
}

function isSharedSecretRequest(req: Request) {
  return Boolean(
    OPS_NOTIFICATION_SECRET &&
      req.headers.get("x-ops-notification-secret") === OPS_NOTIFICATION_SECRET,
  );
}

async function isOpsUserRequest(req: Request) {
  const token = getBearerToken(req);
  if (!token || token === SUPABASE_SERVICE_ROLE_KEY) return false;

  const { data: userData, error: userError } = await supabase.auth.getUser(token);
  const userId = userData?.user?.id;
  if (userError || !userId) return false;

  const { data, error } = await supabase
    .from("app_user_modules")
    .select("module_key")
    .eq("user_id", userId);

  if (error) return false;
  const rows = data ?? [];
  return rows.length === 0 || rows.some((row) => row.module_key === "Ops");
}

function parseBody(req: Request): Promise<NotificationRequest> {
  if (req.method !== "POST") return Promise.resolve({});
  return req
    .json()
    .then((body) => (body && typeof body === "object" ? body : {}))
    .catch(() => ({}));
}

function getPeruToday() {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Lima",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
}

function normalizeLimit(value: unknown) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) return 10;
  return Math.min(Math.trunc(parsed), 10);
}

function normalizeWhatsAppNumber(value: string) {
  const trimmed = value.trim();
  if (trimmed.startsWith("whatsapp:+")) return trimmed;
  if (trimmed.startsWith("+")) return `whatsapp:${trimmed}`;
  return `whatsapp:+${trimmed.replace(/\D/g, "")}`;
}

function formatDateTime(value: unknown) {
  if (!value) return "Sin fecha";
  const text = String(value);
  if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(text) && !/[zZ]|[+-]\d{2}:\d{2}$/.test(text)) {
    return text.slice(0, 16).replace("T", " ");
  }
  const parsed = new Date(text);
  if (Number.isNaN(parsed.getTime())) return text;
  return new Intl.DateTimeFormat("es-PE", {
    timeZone: "America/Lima",
    dateStyle: "short",
    timeStyle: "short",
    hour12: true,
  }).format(parsed);
}

type DateParts = {
  year: string;
  monthIndex: number;
  day: string;
  weekdayIndex: number;
};

function buildDateParts(year: string | undefined, month: string | undefined, day: string | undefined): DateParts | null {
  const monthIndex = Number(month) - 1;
  const yearNumber = Number(year);
  const dayNumber = Number(day);

  if (
    !year ||
    !day ||
    !Number.isInteger(yearNumber) ||
    !Number.isInteger(dayNumber) ||
    monthIndex < 0 ||
    monthIndex >= SPANISH_SHORT_MONTHS.length
  ) {
    return null;
  }

  const date = new Date(Date.UTC(yearNumber, monthIndex, dayNumber));
  if (
    date.getUTCFullYear() !== yearNumber ||
    date.getUTCMonth() !== monthIndex ||
    date.getUTCDate() !== dayNumber
  ) {
    return null;
  }

  return { year, monthIndex, day, weekdayIndex: date.getUTCDay() };
}

function getPeruDateParts(date: Date): DateParts | null {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Lima",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const year = parts.find((part) => part.type === "year")?.value;
  const month = parts.find((part) => part.type === "month")?.value;
  const day = parts.find((part) => part.type === "day")?.value;

  return buildDateParts(year, month, day);
}

function extractDateParts(value: unknown): DateParts | null {
  if (!value) return null;
  const text = String(value).trim();
  const match = text.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (match) {
    return buildDateParts(match[1], match[2], match[3]);
  }

  const parsed = new Date(text);
  if (Number.isNaN(parsed.getTime())) return null;
  return getPeruDateParts(parsed);
}

function formatDailySummaryDate(value: unknown) {
  const parts = extractDateParts(value);
  if (!parts) return "Sin fecha";
  return `${SPANISH_WEEKDAYS[parts.weekdayIndex]}, ${parts.day} ${SPANISH_SHORT_MONTHS[parts.monthIndex]} ${parts.year}`;
}

function formatCriticalOrderDate(value: unknown) {
  const parts = extractDateParts(value);
  if (!parts) return "Sin fecha";
  return `${SPANISH_WEEKDAYS[parts.weekdayIndex]}, ${parts.day} ${SPANISH_SHORT_MONTHS[parts.monthIndex]}`;
}

function compactLine(value: unknown, maxLength = 90) {
  const text = String(value ?? "").replace(/\s+/g, " ").trim();
  if (text.length <= maxLength) return text;
  return `${text.slice(0, maxLength - 3).trim()}...`;
}

function buildCriticalOrdersText(summary: Record<string, unknown>) {
  const orders = Array.isArray(summary.critical_orders) ? summary.critical_orders : [];
  if (orders.length === 0) return "Sin pedidos criticos.";

  return orders
    .slice(0, 10)
    .map((raw, index) => {
      const order = raw as Record<string, unknown>;
      const cod = order.cod ? `#${order.cod}` : "#-";
      const client = compactLine(order.client ?? "-", 32);
      const orderType = compactLine(order.order_type_name ?? "", 52);
      const stage = compactLine(order.current_stage_title ?? "Sin etapa", 42);
      const due = formatCriticalOrderDate(order.delivery_at);
      const processStage = orderType ? `${orderType} > ${stage}` : stage;
      return `${index + 1}. ${cod} ${client} - ${processStage} - ${due}`;
    })
    .join("\n");
}

function buildPriorityTasksText(summary: Record<string, unknown>) {
  const tasks = Array.isArray(summary.priority_tasks) ? summary.priority_tasks : [];
  if (tasks.length === 0) return "Sin tareas pendientes.";

  return tasks
    .slice(0, 10)
    .map((raw, index) => {
      const task = raw as Record<string, unknown>;
      const cod = task.order_cod ? `#${task.order_cod}` : "#-";
      const client = compactLine(task.client ?? "-", 28);
      const stage = compactLine(task.title ?? task.step_code ?? "Sin etapa", 38);
      const due = formatDateTime(task.due_at_local ?? task.due_at);
      return `${index + 1}. ${cod} ${client} - ${stage} - ${due}`;
    })
    .join("\n");
}

function buildDailyMessage(summary: Record<string, unknown>) {
  const link = `${OPS_APP_BASE_URL}/ops/orders`;
  const top = buildCriticalOrdersText(summary);
  const summaryDate = formatDailySummaryDate(summary.date);
  const body = [
    `Resumen OPS ${summaryDate}`,
    `Activos: ${summary.total_pending_orders ?? 0}`,
    `Vencidos: ${summary.overdue_orders ?? 0} | Vencen hoy: ${summary.due_today_orders ?? 0}`,
    `Pendiente: ${summary.pending_status_orders ?? 0} | Procesando: ${summary.processing_status_orders ?? 0}`,
    "",
    "Criticos:",
    top,
    "",
    `Ver pedidos: ${link}`,
  ].join("\n");

  return {
    body,
    contentVariables: {
      "1": summaryDate,
      "2": String(summary.total_pending_orders ?? 0),
      "3": String(summary.overdue_orders ?? 0),
      "4": String(summary.due_today_orders ?? 0),
      "5": String(summary.pending_status_orders ?? 0),
      "6": String(summary.processing_status_orders ?? 0),
      "7": top,
      "8": link,
    },
  };
}

function buildAssigneeMessage(summary: Record<string, unknown>, assigneeId: string | null) {
  const assigneeName = String(summary.assignee_name ?? "Responsable");
  const link = assigneeId
    ? `${OPS_APP_BASE_URL}/ops/inbox?assignee_id=${encodeURIComponent(assigneeId)}`
    : `${OPS_APP_BASE_URL}/ops/inbox`;
  const top = buildPriorityTasksText(summary);
  const body = [
    `Bandeja OPS - ${assigneeName}`,
    `Pendientes: ${summary.total_pending_tasks ?? 0}`,
    `Vencidas: ${summary.overdue_tasks ?? 0} | Vencen hoy: ${summary.due_today_tasks ?? 0}`,
    "",
    "Prioritarias:",
    top,
    "",
    `Ver bandeja: ${link}`,
  ].join("\n");

  return {
    body,
    contentVariables: {
      "1": assigneeName,
      "2": String(summary.total_pending_tasks ?? 0),
      "3": String(summary.overdue_tasks ?? 0),
      "4": String(summary.due_today_tasks ?? 0),
      "5": top,
      "6": link,
    },
  };
}

async function sendWhatsAppMessage(params: {
  to: string;
  body: string;
  contentSid?: string;
  contentVariables?: Record<string, string>;
  dryRun: boolean;
}) {
  const from = normalizeWhatsAppNumber(TWILIO_WHATSAPP_FROM);
  const to = normalizeWhatsAppNumber(params.to);

  if (params.dryRun) {
    return { sid: null, status: "dry_run" };
  }
  if (!TWILIO_ACCOUNT_SID || !TWILIO_AUTH_TOKEN || !TWILIO_WHATSAPP_FROM) {
    throw new Error("Twilio WhatsApp no esta configurado.");
  }

  const form = new URLSearchParams();
  form.set("From", from);
  form.set("To", to);

  if (params.contentSid) {
    form.set("ContentSid", params.contentSid);
    form.set("ContentVariables", JSON.stringify(params.contentVariables ?? {}));
  } else if (TWILIO_ALLOW_FREEFORM_BODY) {
    form.set("Body", params.body);
  } else {
    throw new Error("Falta ContentSid aprobado para envio WhatsApp iniciado por negocio.");
  }

  const response = await fetch(
    `https://api.twilio.com/2010-04-01/Accounts/${TWILIO_ACCOUNT_SID}/Messages.json`,
    {
      method: "POST",
      headers: {
        Authorization: `Basic ${btoa(`${TWILIO_ACCOUNT_SID}:${TWILIO_AUTH_TOKEN}`)}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: form,
    },
  );
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(String(data?.message ?? `Twilio error ${response.status}`));
  }
  return { sid: data?.sid ?? null, status: data?.status ?? null };
}

async function getRecipients(mode: NotificationMode, request: NotificationRequest) {
  let query = supabase
    .from("ops_notification_recipients")
    .select("id, name, whatsapp_to, recipient_type, assignee_id, active, timezone")
    .eq("active", true)
    .order("name");

  if (mode === "daily") {
    query = query.eq("recipient_type", "general");
  } else if (mode === "assignees") {
    query = query.eq("recipient_type", "assignee");
  } else {
    query = query.in("recipient_type", ["general", "assignee"]);
  }

  const recipientIds = [
    ...(request.recipient_id ? [request.recipient_id] : []),
    ...(request.recipient_ids ?? []),
  ].filter(Boolean);
  if (recipientIds.length > 0) {
    query = query.in("id", recipientIds);
  }
  if (request.assignee_id) {
    query = query.eq("assignee_id", request.assignee_id);
  }

  const { data, error } = await query;
  if (error) throw error;
  return (data ?? []) as NotificationRecipient[];
}

async function hasSuccessfulSend(recipient: NotificationRecipient, date: string, type: string) {
  const { data, error } = await supabase
    .from("ops_notification_logs")
    .select("id")
    .eq("notification_date", date)
    .eq("notification_type", type)
    .eq("recipient_id", recipient.id)
    .eq("dry_run", false)
    .eq("status", "success")
    .limit(1);

  if (error) throw error;
  return Boolean(data?.length);
}

async function logNotification(params: {
  date: string;
  type: "daily_summary" | "assignee_summary";
  recipient: NotificationRecipient;
  status: "success" | "error" | "skipped";
  dryRun: boolean;
  sid?: string | null;
  payload: Record<string, unknown>;
  errorMessage?: string | null;
}) {
  await supabase.from("ops_notification_logs").insert({
    notification_date: params.date,
    notification_type: params.type,
    recipient_id: params.recipient.id,
    assignee_id: params.recipient.assignee_id,
    whatsapp_to: params.recipient.whatsapp_to,
    status: params.status,
    dry_run: params.dryRun,
    twilio_message_sid: params.sid ?? null,
    payload: params.payload,
    error_message: params.errorMessage ?? null,
  });
}

function getRelationName(value: unknown) {
  const relation = Array.isArray(value) ? value[0] : value;
  if (!relation || typeof relation !== "object") return "";
  return String((relation as Record<string, unknown>).name ?? "").trim();
}

async function enrichDailySummaryOrderTypes(summary: Record<string, unknown>) {
  const criticalOrders = Array.isArray(summary.critical_orders)
    ? (summary.critical_orders as Record<string, unknown>[])
    : [];
  const orderIds = [
    ...new Set(
      criticalOrders
        .filter((order) => !order.order_type_name && order.id)
        .map((order) => String(order.id)),
    ),
  ];

  if (orderIds.length === 0) return summary;

  const { data, error } = await supabase
    .from("ops_orders")
    .select("id, order_type:ops_order_types(name)")
    .in("id", orderIds);
  if (error) throw error;

  const namesByOrderId = new Map<string, string>();
  for (const row of data ?? []) {
    const name = getRelationName((row as Record<string, unknown>).order_type);
    if (name) namesByOrderId.set(String(row.id), name);
  }

  for (const order of criticalOrders) {
    const name = namesByOrderId.get(String(order.id));
    if (name) order.order_type_name = name;
  }

  return summary;
}

async function buildSummaryForRecipient(
  recipient: NotificationRecipient,
  date: string,
  limit: number,
) {
  if (recipient.recipient_type === "general") {
    const { data, error } = await supabase.rpc("ops_build_daily_order_summary", {
      p_today: date,
      p_limit: limit,
    });
    if (error) throw error;
    const summary = (data ?? {}) as Record<string, unknown>;
    await enrichDailySummaryOrderTypes(summary);
    return {
      type: "daily_summary" as const,
      summary,
      message: buildDailyMessage(summary),
      contentSid: TWILIO_OPS_DAILY_CONTENT_SID,
    };
  }

  if (!recipient.assignee_id) {
    throw new Error("El destinatario responsable no tiene assignee_id.");
  }

  const { data, error } = await supabase.rpc("ops_build_assignee_task_summary", {
    p_assignee_id: recipient.assignee_id,
    p_today: date,
    p_limit: limit,
  });
  if (error) throw error;
  const summary = (data ?? {}) as Record<string, unknown>;
  return {
    type: "assignee_summary" as const,
    summary,
    message: buildAssigneeMessage(summary, recipient.assignee_id),
    contentSid: TWILIO_OPS_ASSIGNEE_CONTENT_SID,
  };
}

async function processRecipient(params: {
  recipient: NotificationRecipient;
  date: string;
  limit: number;
  dryRun: boolean;
  force: boolean;
}) {
  const { recipient, date, limit, dryRun, force } = params;
  const prepared = await buildSummaryForRecipient(recipient, date, limit);

  if (!dryRun && !force && (await hasSuccessfulSend(recipient, date, prepared.type))) {
    const payload = {
      reason: "already_sent",
      recipient_name: recipient.name,
      notification_type: prepared.type,
    };
    await logNotification({
      date,
      type: prepared.type,
      recipient,
      status: "skipped",
      dryRun,
      payload,
    });
    return {
      recipient_id: recipient.id,
      recipient_name: recipient.name,
      notification_type: prepared.type,
      status: "skipped",
      dry_run: dryRun,
      preview: prepared.message.body,
    } satisfies SendResult;
  }

  try {
    const twilio = await sendWhatsAppMessage({
      to: recipient.whatsapp_to,
      body: prepared.message.body,
      contentSid: prepared.contentSid,
      contentVariables: prepared.message.contentVariables,
      dryRun,
    });

    await logNotification({
      date,
      type: prepared.type,
      recipient,
      status: "success",
      dryRun,
      sid: twilio.sid,
      payload: {
        recipient_name: recipient.name,
        summary: prepared.summary,
        message_body: prepared.message.body,
        content_sid: prepared.contentSid || null,
        content_variables: prepared.message.contentVariables,
        twilio_status: twilio.status,
      },
    });

    return {
      recipient_id: recipient.id,
      recipient_name: recipient.name,
      notification_type: prepared.type,
      status: "success",
      dry_run: dryRun,
      twilio_message_sid: twilio.sid,
      preview: prepared.message.body,
    } satisfies SendResult;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await logNotification({
      date,
      type: prepared.type,
      recipient,
      status: "error",
      dryRun,
      payload: {
        recipient_name: recipient.name,
        summary: prepared.summary,
        message_body: prepared.message.body,
        content_sid: prepared.contentSid || null,
        content_variables: prepared.message.contentVariables,
      },
      errorMessage: message,
    });

    return {
      recipient_id: recipient.id,
      recipient_name: recipient.name,
      notification_type: prepared.type,
      status: "error",
      dry_run: dryRun,
      error_message: message,
      preview: prepared.message.body,
    } satisfies SendResult;
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const body = await parseBody(req);
    const dryRun = body.dry_run !== false;
    const canPrivilegedSend = isServiceRoleRequest(req) || isSharedSecretRequest(req);
    const canUserDryRun = await isOpsUserRequest(req);

    if (!canPrivilegedSend && !canUserDryRun) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }
    if (!dryRun && !canPrivilegedSend && !OPS_NOTIFICATION_ALLOW_USER_SEND) {
      return jsonResponse({ error: "Real sends require service role or OPS_NOTIFICATION_SECRET." }, 403);
    }

    const mode = body.mode ?? "daily";
    if (!["daily", "assignees", "all"].includes(mode)) {
      return jsonResponse({ error: "Invalid mode" }, 400);
    }

    const notificationDate = body.notification_date ?? getPeruToday();
    const limit = normalizeLimit(body.limit);
    const recipients = await getRecipients(mode as NotificationMode, body);
    const results: SendResult[] = [];

    for (const recipient of recipients) {
      results.push(
        await processRecipient({
          recipient,
          date: notificationDate,
          limit,
          dryRun,
          force: Boolean(body.force),
        }),
      );
    }

    return jsonResponse({
      ok: true,
      mode,
      dry_run: dryRun,
      notification_date: notificationDate,
      recipients_count: recipients.length,
      results,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("OPS notification failed", error);
    return jsonResponse({ error: message }, 500);
  }
});
