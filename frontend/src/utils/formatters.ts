export function formatCurrency(
  value: number | null | undefined,
  currency = "USD",
): string {
  const amount = typeof value === "number" ? value : 0;
  return new Intl.NumberFormat("es-PE", {
    style: "currency",
    currency,
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(amount);
}

export function formatDate(value?: string | null): string {
  if (!value) return "—";
  try {
    return new Intl.DateTimeFormat("es-PE", {
      day: "2-digit",
      month: "short",
      year: "numeric",
    }).format(new Date(value));
  } catch (error) {
    console.error("Invalid date value", value, error);
    return value;
  }
}
