# main.py — Noga Marks API (versión ecommerce estable sin Lead Hunter)
import os, hmac, hashlib, base64, json, traceback, smtplib, secrets, requests, csv, io
from enum import Enum
from decimal import Decimal, ROUND_HALF_UP
from typing import Any, Dict, Optional, List, Tuple
from uuid import UUID, uuid4
from fastapi import FastAPI, Request, HTTPException, UploadFile, File
from fastapi.responses import JSONResponse
from supabase import create_client, Client
from dotenv import load_dotenv
from datetime import datetime, date
from urllib.parse import parse_qs
from twilio.rest import Client as TwilioClient
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from fastapi_utils.tasks import repeat_every
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

# === Cargar variables ===
load_dotenv()



app = FastAPI(title="Noga Marks API", version="1.2.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],       # en producción cambia esto por los dominios permitidos
    allow_methods=["*"],
    allow_headers=["*"],
    allow_credentials=True,
)


# === Configuración general ===
SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_KEY = os.getenv("SUPABASE_KEY", "")
WOO_SECRET = os.getenv("WOO_SECRET", "")
DEBUG_MODE = os.getenv("DEBUG", "false").lower() == "true"

TWILIO_SID = os.getenv("TWILIO_ACCOUNT_SID")
TWILIO_TOKEN = os.getenv("TWILIO_AUTH_TOKEN")
TWILIO_FROM = os.getenv("TWILIO_WHATSAPP_FROM")
TWILIO_TO_DEFAULT = os.getenv("TWILIO_WHATSAPP_TO")

WOO_API_URL = os.getenv("WOO_API_URL", "")
WOO_CONSUMER_KEY = os.getenv("WOO_CONSUMER_KEY", "")
WOO_CONSUMER_SECRET = os.getenv("WOO_CONSUMER_SECRET", "")

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

FULFILLMENT_STATUSES = {"processing", "completed", "on-hold"}


# === Helpers ===
def valid_signature(payload: bytes, signature_b64: str) -> bool:
    """Verifica la firma HMAC enviada por WooCommerce."""
    if DEBUG_MODE:
        return True
    if not signature_b64 or not WOO_SECRET:
        return False
    digest = hmac.new(WOO_SECRET.encode(), payload, hashlib.sha256).digest()
    expected = base64.b64encode(digest).decode()
    return hmac.compare_digest(expected, signature_b64)


def upsert_contact_and_get_id(email: str | None, name: str | None, phone: str | None):
    """Crea o actualiza contacto en Supabase y devuelve su ID."""
    if not email:
        return None
    supabase.table("contacts").upsert({
        "email": email,
        "name": name,
        "phone": phone,
        "created_at": datetime.utcnow().isoformat()
    }).execute()

    res = supabase.table("contacts").select("id").eq("email", email).limit(1).execute()
    if res.data and len(res.data) > 0:
        return res.data[0].get("id")
    return None


# === Nuevos modelos de inventario y compras ===
class CategoryBase(BaseModel):
    code: str = Field(..., max_length=64)
    name: str = Field(..., max_length=255)
    parent_id: Optional[UUID] = None
    is_active: bool = True


class CategoryCreate(CategoryBase):
    pass


class CategoryUpdate(BaseModel):
    code: Optional[str] = Field(None, max_length=64)
    name: Optional[str] = Field(None, max_length=255)
    parent_id: Optional[UUID] = None
    is_active: Optional[bool] = None


class ProductBase(BaseModel):
    sku: str = Field(..., max_length=128)
    name: str = Field(..., max_length=255)
    description: Optional[str] = None
    category_id: Optional[UUID] = None
    woo_product_id: Optional[int] = None
    woo_variant_id: Optional[int] = None
    unit_cost: Optional[float] = None
    unit_price: Optional[float] = None
    status: str = Field(default="active", max_length=32)
    attributes: Dict[str, Any] = Field(default_factory=dict)
    metadata: Dict[str, Any] = Field(default_factory=dict)


class ProductCreate(ProductBase):
    pass


class ProductUpdate(BaseModel):
    name: Optional[str] = Field(None, max_length=255)
    description: Optional[str] = None
    category_id: Optional[UUID] = None
    woo_product_id: Optional[int] = None
    woo_variant_id: Optional[int] = None
    unit_cost: Optional[float] = None
    unit_price: Optional[float] = None
    status: Optional[str] = Field(None, max_length=32)
    attributes: Optional[Dict[str, Any]] = None
    metadata: Optional[Dict[str, Any]] = None


class SupplierBase(BaseModel):
    name: str = Field(..., max_length=255)
    tax_id: Optional[str] = Field(None, max_length=64)
    email: Optional[str] = Field(None, max_length=255)
    phone: Optional[str] = Field(None, max_length=64)
    address: Dict[str, Any] = Field(default_factory=dict)
    payment_terms: Optional[str] = Field(None, max_length=255)
    lead_time_days: Optional[int] = None
    is_active: bool = True
    metadata: Dict[str, Any] = Field(default_factory=dict)


class SupplierCreate(SupplierBase):
    pass


class SupplierUpdate(BaseModel):
    name: Optional[str] = Field(None, max_length=255)
    tax_id: Optional[str] = Field(None, max_length=64)
    email: Optional[str] = Field(None, max_length=255)
    phone: Optional[str] = Field(None, max_length=64)
    address: Optional[Dict[str, Any]] = None
    payment_terms: Optional[str] = Field(None, max_length=255)
    lead_time_days: Optional[int] = None
    is_active: Optional[bool] = None
    metadata: Optional[Dict[str, Any]] = None


class MovementDirection(str, Enum):
    IN = "in"
    OUT = "out"


class MovementCreate(BaseModel):
    product_id: UUID
    movement_type: str = Field(..., max_length=64)
    direction: MovementDirection
    quantity: float = Field(..., gt=0)
    unit_cost: Optional[float] = Field(None, ge=0)
    reference_type: Optional[str] = Field(None, max_length=64)
    reference_id: Optional[UUID] = None
    notes: Optional[str] = None
    occurred_at: Optional[datetime] = None


class PurchaseOrderLineInput(BaseModel):
    product_id: UUID
    quantity_ordered: float = Field(..., gt=0)
    unit_cost: float = Field(..., ge=0)
    tax_rate: float = Field(default=0, ge=0)
    expected_receipt_date: Optional[date] = None
    metadata: Dict[str, Any] = Field(default_factory=dict)


class PurchaseOrderCreate(BaseModel):
    supplier_id: UUID
    expected_date: Optional[date] = None
    currency: str = Field(default="USD", max_length=8)
    notes: Optional[str] = None
    items: List[PurchaseOrderLineInput]


class PurchaseOrderUpdate(BaseModel):
    expected_date: Optional[date] = None
    currency: Optional[str] = Field(None, max_length=8)
    notes: Optional[str] = None
    items: Optional[List[PurchaseOrderLineInput]] = None
    supplier_id: Optional[UUID] = None


class PurchaseOrderApprove(BaseModel):
    approved_by: Optional[UUID] = None


class PurchaseOrderCancel(BaseModel):
    reason: Optional[str] = Field(None, max_length=512)


class PurchaseOrderReceiveItem(BaseModel):
    line_id: UUID
    quantity: float = Field(..., gt=0)
    unit_cost: Optional[float] = Field(None, ge=0)
    notes: Optional[str] = None


class PurchaseOrderReceive(BaseModel):
    received_by: Optional[UUID] = None
    reference_number: Optional[str] = Field(None, max_length=128)
    notes: Optional[str] = Field(None, max_length=1024)
    items: List[PurchaseOrderReceiveItem]


def supabase_payload(model: BaseModel) -> Dict[str, Any]:
    """Convierte un modelo Pydantic en un dict listo para Supabase."""
    return json.loads(model.model_dump_json(exclude_unset=True))


def supabase_run(query, error_detail: str):
    """Ejecuta consultas Supabase y maneja errores."""
    try:
        result = query.execute()
    except Exception as exc:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"{error_detail}: {exc}") from exc

    error = getattr(result, "error", None)
    if error:
        detail = error.get("message") if isinstance(error, dict) else str(error)
        raise HTTPException(status_code=400, detail=f"{error_detail}: {detail}")
    return result.data


def parse_float(value: Any, default: float = 0.0) -> float:
    """Convierte cadenas numéricas de WooCommerce a float."""
    if value is None:
        return default
    if isinstance(value, (int, float)):
        return float(value)
    try:
        text = str(value).strip().replace(",", "")
        return float(text) if text else default
    except (TypeError, ValueError):
        return default


def clean_str(value: Any) -> str:
    """Convierte a str y limpia espacios."""
    return str(value).strip() if value is not None else ""


def add_error(errors: List[Dict[str, Any]], row_number: int, field: str, message: str):
    errors.append({"row": row_number, "field": field, "error": message})


def parse_int_field(value: Any, field: str, row_number: int, errors: List[Dict[str, Any]]) -> Optional[int]:
    text = clean_str(value)
    if text == "":
        add_error(errors, row_number, field, "Valor requerido")
        return None
    try:
        return int(text)
    except ValueError:
        add_error(errors, row_number, field, "Debe ser un número entero")
        return None


def parse_float_field(value: Any, field: str, row_number: int, errors: List[Dict[str, Any]], allow_empty: bool = True) -> Optional[float]:
    text = clean_str(value)
    if text == "":
        if allow_empty:
            return None
        add_error(errors, row_number, field, "Valor requerido")
        return None
    try:
        return float(text.replace(",", ""))
    except ValueError:
        add_error(errors, row_number, field, "Debe ser un número")
        return None


async def read_csv_upload(file: UploadFile, required_columns: List[str]) -> List[Dict[str, str]]:
    """Lee un CSV subido y valida que tenga encabezados requeridos."""
    content = await file.read()
    try:
        text = content.decode("utf-8-sig")
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"No se pudo leer el archivo: {exc}") from exc

    reader = csv.DictReader(io.StringIO(text))
    if not reader.fieldnames:
        raise HTTPException(status_code=400, detail="El CSV no tiene encabezados")

    missing = [col for col in required_columns if col not in reader.fieldnames]
    if missing:
        raise HTTPException(status_code=400, detail=f"Faltan columnas requeridas: {', '.join(missing)}")

    rows = list(reader)
    if not rows:
        raise HTTPException(status_code=400, detail="El CSV está vacío")

    return rows


def find_inventory_product(woo_product_id: Optional[int], woo_variant_id: Optional[int]) -> Optional[Dict[str, Any]]:
    """Busca el producto en inventario en base al ID de WooCommerce."""
    if woo_variant_id:
        data = supabase_run(
            supabase.table("inv_products").select("id, sku, name").eq("woo_variant_id", woo_variant_id).limit(1),
            "No se pudo buscar producto por variante de WooCommerce"
        )
        if data:
            return data[0]
    if woo_product_id:
        data = supabase_run(
            supabase.table("inv_products").select("id, sku, name").eq("woo_product_id", woo_product_id).limit(1),
            "No se pudo buscar producto por ID de WooCommerce"
        )
        if data:
        return data[0]
    return None


# === Importaciones CSV (Fase 2) ===
def fetch_id_map(table: str, key_column: str, id_column: str, values: List[str], error_detail: str) -> Dict[str, str]:
    """Obtiene un mapa clave->id en Supabase para un set de valores."""
    unique_values = list({v for v in values if v})
    if not unique_values:
        return {}

    results: Dict[str, str] = {}
    chunk_size = 500
    for i in range(0, len(unique_values), chunk_size):
        batch = unique_values[i : i + chunk_size]
        data = supabase_run(
            supabase.table(table).select(f"{id_column}, {key_column}").in_(key_column, batch),
            error_detail,
        )
        for item in data or []:
            results[item[key_column]] = item[id_column]
    return results


def insert_import_batch(kind: str) -> str:
    batch_id = str(uuid4())
    supabase_run(
        supabase.table("import_batches").insert({"id": batch_id, "kind": kind, "status": "pending"}),
        "No se pudo registrar el lote de importación",
    )
    return batch_id


def complete_import_batch(batch_id: str, status: str = "completed", error_summary: Optional[Dict[str, Any]] = None):
    payload: Dict[str, Any] = {"status": status}
    if error_summary is not None:
        payload["error_summary"] = error_summary
    supabase_run(
        supabase.table("import_batches").update(payload).eq("id", batch_id),
        "No se pudo actualizar el estado del lote de importación",
    )


@app.post("/imports/products", status_code=201)
async def import_products_csv(file: UploadFile = File(...)):
    """Importa catálogo de productos desde CSV. Aborta si hay errores."""
    rows = await read_csv_upload(file, ["sku", "name", "category", "price", "cost", "status"])
    errors: List[Dict[str, Any]] = []
    products: List[Dict[str, Any]] = []
    raw_rows: List[Dict[str, Any]] = []

    for idx, row in enumerate(rows):
        row_number = idx + 2  # +1 por header, +1 por base 1
        row_errors: List[Dict[str, Any]] = []

        sku = clean_str(row.get("sku"))
        name = clean_str(row.get("name"))
        category = clean_str(row.get("category"))
        status = clean_str(row.get("status")) or "active"
        price = parse_float_field(row.get("price"), "price", row_number, row_errors, allow_empty=True)
        cost = parse_float_field(row.get("cost"), "cost", row_number, row_errors, allow_empty=True)

        if not sku:
            add_error(row_errors, row_number, "sku", "SKU requerido")
        if not name:
            add_error(row_errors, row_number, "name", "Nombre requerido")

        raw_rows.append(
            {
                "batch_id": None,  # se asignará al guardar
                "row_number": row_number,
                "sku": sku,
                "name": name,
                "category": category,
                "price": price,
                "cost": cost,
                "status": status,
                "errors": "; ".join(err["error"] for err in row_errors) if row_errors else None,
            }
        )

        if row_errors:
            errors.extend(row_errors)
            continue

        products.append(
            {
                "sku": sku,
                "name": name,
                "category": category or None,
                "price": price,
                "cost": cost,
                "status": status or "active",
            }
        )

    if errors:
        raise HTTPException(status_code=400, detail={"message": "Errores de validación", "errors": errors})

    batch_id = insert_import_batch("products")
    # guardar raw con batch asignado (solo si hay filas)
    if raw_rows:
        for r in raw_rows:
            r["batch_id"] = batch_id
        supabase_run(
            supabase.table("raw_products").insert(raw_rows),
            "No se pudo registrar las filas de productos",
        )

    supabase_run(
        supabase.table("products").upsert(products, on_conflict="sku"),
        "No se pudo importar productos",
    )
    complete_import_batch(batch_id, status="completed")

    return {"imported": len(products), "errors": []}


@app.post("/imports/sales", status_code=201)
async def import_sales_csv(file: UploadFile = File(...)):
    """Importa ventas históricas desde CSV. Aborta si hay errores."""
    rows = await read_csv_upload(file, ["sku", "store_code", "sale_date", "units_sold", "revenue"])
    errors: List[Dict[str, Any]] = []
    sales: List[Dict[str, Any]] = []
    raw_rows: List[Dict[str, Any]] = []

    # Prefetch mappings
    skus = [clean_str(r.get("sku")) for r in rows]
    store_codes = [clean_str(r.get("store_code")) for r in rows]

    product_map = fetch_id_map("products", "sku", "id", skus, "No se pudo obtener productos")
    missing_skus = [sku for sku in set(skus) if sku and sku not in product_map]
    if missing_skus:
        for sku in missing_skus:
            errors.append({"row": None, "field": "sku", "error": f"SKU no encontrado: {sku}"})

    # Crear tiendas faltantes con nombre = code
    existing_store_map = fetch_id_map("stores", "code", "id", store_codes, "No se pudo obtener tiendas")
    missing_stores = [code for code in set(store_codes) if code and code not in existing_store_map]
    if missing_stores:
        supabase_run(
            supabase.table("stores").upsert(
                [{"code": code, "name": code, "channel": "unspecified"} for code in missing_stores],
                on_conflict="code",
            ),
            "No se pudieron crear tiendas faltantes",
        )
        # refrescar mapa
        existing_store_map = fetch_id_map("stores", "code", "id", store_codes, "No se pudo obtener tiendas")

    for idx, row in enumerate(rows):
        row_number = idx + 2
        row_errors: List[Dict[str, Any]] = []

        sku = clean_str(row.get("sku"))
        store_code = clean_str(row.get("store_code"))
        sale_date_raw = clean_str(row.get("sale_date"))
        units_sold = parse_int_field(row.get("units_sold"), "units_sold", row_number, row_errors)
        revenue = parse_float_field(row.get("revenue"), "revenue", row_number, row_errors, allow_empty=True)

        if not sku:
            add_error(row_errors, row_number, "sku", "SKU requerido")
        if not store_code:
            add_error(row_errors, row_number, "store_code", "store_code requerido")

        try:
            sale_date_parsed = datetime.fromisoformat(sale_date_raw).date() if sale_date_raw else None
        except ValueError:
            add_error(row_errors, row_number, "sale_date", "Fecha inválida, usa YYYY-MM-DD")
            sale_date_parsed = None

        if sku and sku not in product_map:
            add_error(row_errors, row_number, "sku", f"SKU no encontrado: {sku}")
        if store_code and store_code not in existing_store_map:
            add_error(row_errors, row_number, "store_code", f"Tienda no encontrada: {store_code}")

        raw_rows.append(
            {
                "batch_id": None,
                "row_number": row_number,
                "sku": sku,
                "store_code": store_code,
                "sale_date": sale_date_parsed.isoformat() if sale_date_parsed else None,
                "units_sold": units_sold,
                "revenue": revenue,
                "errors": "; ".join(err["error"] for err in row_errors) if row_errors else None,
            }
        )

        if row_errors:
            errors.extend(row_errors)
            continue

        sales.append(
            {
                "product_id": product_map[sku],
                "store_id": existing_store_map[store_code],
                "sale_date": sale_date_parsed.isoformat(),
                "units_sold": units_sold,
                "revenue": revenue,
            }
        )

    if errors:
        raise HTTPException(status_code=400, detail={"message": "Errores de validación", "errors": errors})

    batch_id = insert_import_batch("sales")
    if raw_rows:
        for r in raw_rows:
            r["batch_id"] = batch_id
        supabase_run(
            supabase.table("raw_sales_history").insert(raw_rows),
            "No se pudo registrar las filas de ventas",
        )

    supabase_run(
        supabase.table("sales_history").upsert(sales, on_conflict="product_id,store_id,sale_date"),
        "No se pudo importar ventas",
    )
    complete_import_batch(batch_id, status="completed")

    return {"imported": len(sales), "errors": []}


@app.post("/imports/inventory", status_code=201)
async def import_inventory_csv(file: UploadFile = File(...)):
    """Importa inventario actual desde CSV. Aborta si hay errores."""
    rows = await read_csv_upload(file, ["sku", "store_code", "on_hand", "cover_days"])
    errors: List[Dict[str, Any]] = []
    inventory_rows: List[Dict[str, Any]] = []
    raw_rows: List[Dict[str, Any]] = []

    skus = [clean_str(r.get("sku")) for r in rows]
    store_codes = [clean_str(r.get("store_code")) for r in rows]

    product_map = fetch_id_map("products", "sku", "id", skus, "No se pudo obtener productos")
    missing_skus = [sku for sku in set(skus) if sku and sku not in product_map]
    if missing_skus:
        for sku in missing_skus:
            errors.append({"row": None, "field": "sku", "error": f"SKU no encontrado: {sku}"})

    existing_store_map = fetch_id_map("stores", "code", "id", store_codes, "No se pudo obtener tiendas")
    missing_stores = [code for code in set(store_codes) if code and code not in existing_store_map]
    if missing_stores:
        supabase_run(
            supabase.table("stores").upsert(
                [{"code": code, "name": code, "channel": "unspecified"} for code in missing_stores],
                on_conflict="code",
            ),
            "No se pudieron crear tiendas faltantes",
        )
        existing_store_map = fetch_id_map("stores", "code", "id", store_codes, "No se pudo obtener tiendas")

    for idx, row in enumerate(rows):
        row_number = idx + 2
        row_errors: List[Dict[str, Any]] = []

        sku = clean_str(row.get("sku"))
        store_code = clean_str(row.get("store_code"))
        on_hand = parse_int_field(row.get("on_hand"), "on_hand", row_number, row_errors)
        cover_days = parse_int_field(row.get("cover_days"), "cover_days", row_number, row_errors)

        if not sku:
            add_error(row_errors, row_number, "sku", "SKU requerido")
        if not store_code:
            add_error(row_errors, row_number, "store_code", "store_code requerido")

        if sku and sku not in product_map:
            add_error(row_errors, row_number, "sku", f"SKU no encontrado: {sku}")
        if store_code and store_code not in existing_store_map:
            add_error(row_errors, row_number, "store_code", f"Tienda no encontrada: {store_code}")

        raw_rows.append(
            {
                "batch_id": None,
                "row_number": row_number,
                "sku": sku,
                "store_code": store_code,
                "on_hand": on_hand,
                "cover_days": cover_days,
                "errors": "; ".join(err["error"] for err in row_errors) if row_errors else None,
            }
        )

        if row_errors:
            errors.extend(row_errors)
            continue

        inventory_rows.append(
            {
                "product_id": product_map[sku],
                "store_id": existing_store_map[store_code],
                "on_hand": on_hand,
                "cover_days": cover_days,
                "updated_at": datetime.utcnow().isoformat(),
            }
        )

    if errors:
        raise HTTPException(status_code=400, detail={"message": "Errores de validación", "errors": errors})

    batch_id = insert_import_batch("inventory")
    if raw_rows:
        for r in raw_rows:
            r["batch_id"] = batch_id
        supabase_run(
            supabase.table("raw_inventory").insert(raw_rows),
            "No se pudo registrar las filas de inventario",
        )

    supabase_run(
        supabase.table("inventory").upsert(inventory_rows, on_conflict="product_id,store_id"),
        "No se pudo importar inventario",
    )
    complete_import_batch(batch_id, status="completed")

    return {"imported": len(inventory_rows), "errors": []}

def woo_rest_request(method: str, endpoint: str, params: Optional[Dict[str, Any]] = None) -> Any:
    """Realiza una llamada autenticada al API REST de WooCommerce."""
    if not (WOO_API_URL and WOO_CONSUMER_KEY and WOO_CONSUMER_SECRET):
        raise HTTPException(status_code=500, detail="WooCommerce API no está configurado en el backend")

    url = f"{WOO_API_URL.rstrip('/')}/wp-json/wc/v3/{endpoint.lstrip('/')}"
    try:
        response = requests.request(
            method=method.upper(),
            url=url,
            params=params,
            auth=(WOO_CONSUMER_KEY, WOO_CONSUMER_SECRET),
            timeout=30
        )
    except requests.RequestException as exc:
        raise HTTPException(status_code=502, detail=f"WooCommerce API no disponible: {exc}") from exc

    if response.status_code >= 400:
        try:
            detail = response.json()
        except ValueError:
            detail = response.text
        raise HTTPException(
            status_code=response.status_code,
            detail=f"Error WooCommerce {response.status_code}: {detail}"
        )

    try:
        return response.json()
    except ValueError:
        return {}


def fetch_all_woo_products() -> List[Dict[str, Any]]:
    """Obtiene todos los productos publicados en WooCommerce."""
    all_products: List[Dict[str, Any]] = []
    page = 1
    per_page = 50

    while True:
        params = {"page": page, "per_page": per_page, "status": "any"}
        data = woo_rest_request("GET", "products", params=params)
        if not isinstance(data, list):
            break
        all_products.extend(data)
        if len(data) < per_page:
            break
        page += 1
    return all_products


def fetch_woo_variations(product_id: int) -> List[Dict[str, Any]]:
    """Obtiene las variaciones de un producto variable."""
    variations: List[Dict[str, Any]] = []
    page = 1
    per_page = 50
    while True:
        endpoint = f"products/{product_id}/variations"
        params = {"page": page, "per_page": per_page}
        data = woo_rest_request("GET", endpoint, params=params)
        if not isinstance(data, list) or not data:
            break
        variations.extend(data)
        if len(data) < per_page:
            break
        page += 1
    return variations


def build_inventory_payload_from_woo(
    product: Dict[str, Any],
    variation: Optional[Dict[str, Any]] = None
) -> Dict[str, Any]:
    """Convierte un producto (o variación) de WooCommerce a inv_products."""
    source = variation or product
    is_variant = variation is not None

    woo_product_id = product.get("id")
    woo_variant_id = source.get("id") if is_variant else None

    raw_sku = source.get("sku") or product.get("sku")
    sku = (raw_sku or f"WOO-{woo_variant_id or woo_product_id}").strip()

    name = source.get("name") or product.get("name") or sku
    status = product.get("status", "draft")
    attributes = source.get("attributes") if is_variant else product.get("attributes")

    record: Dict[str, Any] = {
        "sku": sku,
        "name": name,
        "description": product.get("short_description") or product.get("description"),
        "category_id": None,
        "woo_product_id": woo_product_id,
        "woo_variant_id": woo_variant_id,
        "unit_cost": parse_float(source.get("regular_price") or source.get("price")),
        "unit_price": parse_float(source.get("price")),
        "status": "active" if status in {"publish", "private"} else "inactive",
        "attributes": attributes or [],
        "metadata": {
            "type": product.get("type"),
            "manage_stock": source.get("manage_stock"),
            "stock_quantity": source.get("stock_quantity"),
            "raw": source
        }
    }
    return record


def chunk_list(items: List[Dict[str, Any]], size: int = 100) -> List[List[Dict[str, Any]]]:
    return [items[i:i + size] for i in range(0, len(items), size)]


def fetch_sales_order_by_woo_id(woo_order_id: int) -> Optional[Dict[str, Any]]:
    data = supabase_run(
        supabase.table("sales_orders").select("*").eq("woo_order_id", woo_order_id).limit(1),
        "No se pudo recuperar la orden de venta"
    )
    return data[0] if data else None


def ensure_product_exists(product_id: UUID) -> Dict[str, Any]:
    """Valida que el producto exista antes de operar con inventario."""
    data = supabase_run(
        supabase.table("inv_products").select("id, sku, name").eq("id", str(product_id)).limit(1),
        "No se pudo verificar el producto"
    )
    if not data:
        raise HTTPException(status_code=404, detail="Producto no encontrado")
    return data[0]


def get_stock_record(product_id: UUID) -> Optional[Dict[str, Any]]:
    """Obtiene el registro de stock actual para un producto."""
    data = supabase_run(
        supabase.table("inv_stock_levels").select("*").eq("product_id", str(product_id)).limit(1),
        "No se pudo obtener el stock actual"
    )
    return data[0] if data else None


def calculate_stock_transition(payload: MovementCreate) -> Dict[str, Any]:
    """Calcula el nuevo estado de inventario sin aplicar cambios todavía."""
    ensure_product_exists(payload.product_id)
    stock_row = get_stock_record(payload.product_id)
    on_hand = float(stock_row.get("on_hand") or 0) if stock_row else 0.0
    allocated = float(stock_row.get("allocated") or 0) if stock_row else 0.0
    quantity = float(payload.quantity)

    if payload.direction == MovementDirection.OUT:
        new_on_hand = on_hand - quantity
        if new_on_hand < -1e-6:
            raise HTTPException(status_code=400, detail="Stock insuficiente para realizar la salida")
    else:
        new_on_hand = on_hand + quantity

    new_available = new_on_hand - allocated
    return {
        "previous": stock_row,
        "new_on_hand": new_on_hand,
        "new_available": new_available,
        "allocated": allocated
    }


def persist_stock_transition(product_id: UUID, transition: Dict[str, Any]) -> Dict[str, Any]:
    """Persiste los cambios de inventario calculados."""
    previous = transition.get("previous")
    new_on_hand = transition["new_on_hand"]
    new_available = transition["new_available"]
    allocated = transition.get("allocated", 0.0)

    if previous:
        supabase_run(
            supabase.table("inv_stock_levels").update({
                "on_hand": new_on_hand,
                "available": new_available
            }).eq("product_id", str(product_id)),
            "No se pudo actualizar el nivel de stock"
        )
    else:
        supabase_run(
            supabase.table("inv_stock_levels").insert({
                "product_id": str(product_id),
                "on_hand": new_on_hand,
                "allocated": allocated,
                "available": new_available,
                "safety_stock": 0
            }),
            "No se pudo crear el registro de stock"
        )

    refreshed = get_stock_record(product_id)
    if refreshed:
        return refreshed
    return {
        "product_id": str(product_id),
        "on_hand": new_on_hand,
        "allocated": allocated,
        "available": new_available,
        "safety_stock": 0
    }


def apply_inventory_movement(payload: MovementCreate) -> Dict[str, Any]:
    """Inserta un movimiento y aplica el nuevo estado de inventario."""
    transition = calculate_stock_transition(payload)
    movement_data = supabase_payload(payload)
    if "occurred_at" not in movement_data:
        movement_data["occurred_at"] = datetime.utcnow().isoformat()
    movement_data["product_id"] = str(payload.product_id)

    inserted = supabase_run(
        supabase.table("inv_movements").insert(movement_data),
        "No se pudo registrar el movimiento de inventario"
    )
    movement_record = inserted[0] if inserted else movement_data

    try:
        stock_record = persist_stock_transition(payload.product_id, transition)
    except HTTPException:
        movement_id = movement_record.get("id")
        if movement_id:
            try:
                supabase.table("inv_movements").delete().eq("id", movement_id).execute()
            except Exception:
                traceback.print_exc()
        raise

    return {"movement": movement_record, "stock": stock_record}


def ensure_supplier_exists(supplier_id: UUID) -> Dict[str, Any]:
    """Valida que el proveedor exista."""
    result = supabase_run(
        supabase.table("po_suppliers").select("id,name").eq("id", str(supplier_id)).limit(1),
        "No se pudo verificar el proveedor"
    )
    if not result:
        raise HTTPException(status_code=404, detail="Proveedor no encontrado")
    return result[0]


def generate_po_number() -> str:
    """Genera un número de orden único."""
    today = datetime.utcnow().strftime("%Y%m%d")
    suffix = secrets.token_hex(2).upper()
    return f"PO-{today}-{suffix}"


def upsert_sales_order(order: Dict[str, Any]) -> Dict[str, Any]:
    """Crea o actualiza la orden de venta desde WooCommerce."""
    woo_order_id = order.get("id")
    if not woo_order_id:
        raise HTTPException(status_code=400, detail="Pedido de WooCommerce sin ID")

    billing = order.get("billing", {}) or {}
    shipping_lines = order.get("shipping_lines") or []
    payment_status = "paid" if order.get("date_paid") else "unpaid"

    order_payload = {
        "woo_order_id": woo_order_id,
        "status": order.get("status", "created"),
        "order_number": order.get("number") or str(woo_order_id),
        "order_date": order.get("date_created"),
        "customer_email": billing.get("email"),
        "total_amount": parse_float(order.get("total")),
        "currency": order.get("currency") or "USD",
        "payment_status": payment_status,
        "shipping_method": ", ".join(filter(None, [line.get("method_title") for line in shipping_lines])),
        "raw_payload": order
    }

    upserted = supabase_run(
        supabase.table("sales_orders").upsert(order_payload, on_conflict="woo_order_id"),
        "No se pudo registrar la orden de venta"
    )
    if upserted:
        return upserted[0]
    existing = fetch_sales_order_by_woo_id(woo_order_id)
    if existing:
        return existing
    raise HTTPException(status_code=500, detail="No se pudo recuperar la orden de venta registrada")


def sync_sales_order_lines(order_id: UUID, line_items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Sincroniza las líneas de la orden de venta con inventario."""
    supabase_run(
        supabase.table("sales_order_lines").delete().eq("sales_order_id", str(order_id)),
        "No se pudieron limpiar las líneas de venta previas"
    )

    records: List[Dict[str, Any]] = []
    product_cache: Dict[Tuple[Optional[int], Optional[int]], Optional[Dict[str, Any]]] = {}

    for item in line_items:
        woo_product_id = item.get("product_id")
        woo_variant_id = item.get("variation_id")
        cache_key = (woo_product_id, woo_variant_id)

        if cache_key not in product_cache:
            product_cache[cache_key] = find_inventory_product(woo_product_id, woo_variant_id)
        product_info = product_cache[cache_key]

        quantity = parse_float(item.get("quantity"), default=0.0)
        if quantity <= 0:
            continue

        record: Dict[str, Any] = {
            "sales_order_id": str(order_id),
            "product_id": product_info.get("id") if product_info else None,
            "woo_item_id": item.get("id"),
            "quantity": quantity,
            "unit_price": parse_float(item.get("price"), default=0.0),
            "tax_rate": parse_float(item.get("total_tax"), default=0.0),
            "metadata": item
        }
        records.append(record)

    if records:
        supabase_run(
            supabase.table("sales_order_lines").insert(records),
            "No se pudieron registrar las líneas de la orden de venta"
        )

    return records


def movements_exist_for_sales_order(order_id: UUID) -> bool:
    result = supabase_run(
        supabase.table("inv_movements")
        .select("id")
        .eq("reference_type", "sales_order")
        .eq("reference_id", str(order_id))
        .limit(1),
        "No se pudo verificar movimientos existentes"
    )
    return bool(result)


def create_movements_for_sales_order(order: Dict[str, Any], line_records: List[Dict[str, Any]]):
    """Genera salidas de inventario por cada línea de venta si corresponde."""
    if order.get("status") not in FULFILLMENT_STATUSES:
        return
    order_id = order.get("id")
    if not order_id:
        return
    order_uuid = UUID(order_id)

    if movements_exist_for_sales_order(order_uuid):
        return

    for line in line_records:
        product_id = line.get("product_id")
        quantity = parse_float(line.get("quantity"), default=0.0)
        if not product_id or quantity <= 0:
            continue

        movement_payload = MovementCreate(
            product_id=UUID(product_id),
            movement_type="sale",
            direction=MovementDirection.OUT,
            quantity=quantity,
            unit_cost=None,
            reference_type="sales_order",
            reference_id=order_uuid,
            notes=f"Salida por venta WooCommerce #{order.get('order_number')}"
        )
        apply_inventory_movement(movement_payload)


def process_woocommerce_sales_order(order: Dict[str, Any]):
    """Procesa la orden de WooCommerce para actualizar ventas e inventario."""
    sales_order = upsert_sales_order(order)
    order_uuid = UUID(sales_order["id"])
    line_records = sync_sales_order_lines(order_uuid, order.get("line_items", []))
    create_movements_for_sales_order(sales_order, line_records)


def fetch_purchase_order(order_id: UUID) -> Dict[str, Any]:
    """Obtiene una orden de compra con sus relaciones."""
    data = supabase_run(
        supabase.table("po_orders")
        .select("*,po_suppliers(*),po_order_lines(*,inv_products(name,sku))")
        .eq("id", str(order_id))
        .limit(1),
        "No se pudo obtener la orden de compra"
    )
    if not data:
        raise HTTPException(status_code=404, detail="Orden de compra no encontrada")
    order = data[0]
    lines = order.get("po_order_lines") or []
    enriched_lines = []
    for item in lines:
        product = item.pop("inv_products", None)
        if product:
            item["product"] = product
        enriched_lines.append(item)
    order["po_order_lines"] = sorted(enriched_lines, key=lambda item: item.get("created_at") or item.get("id"))
    return order


def recalculate_po_total(order_id: UUID) -> float:
    """Recalcula el total de la orden a partir de sus líneas."""
    lines = supabase_run(
        supabase.table("po_order_lines")
        .select("quantity_ordered,unit_cost")
        .eq("order_id", str(order_id)),
        "No se pudo recalcular el total de la orden de compra"
    )
    total = Decimal("0")
    for line in lines:
        qty = Decimal(str(line.get("quantity_ordered") or 0))
        cost = Decimal(str(line.get("unit_cost") or 0))
        total += qty * cost

    total_float = float(total.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))
    supabase_run(
        supabase.table("po_orders").update({"total_amount": total_float}).eq("id", str(order_id)),
        "No se pudo actualizar el total de la orden de compra"
    )
    return total_float


# === Rutas base ===
@app.get("/")
def root():
    return {"status": "ok", "service": "Noga Marks E-Commerce API"}


@app.get("/health")
def health():
    return {"ok": True}


# === Catalogo y proveedores ===
@app.get("/catalog/categories")
async def list_categories():
    data = supabase_run(
        supabase.table("inv_categories").select("*").order("name"),
        "No se pudo obtener la lista de categorias"
    )
    return data


@app.post("/catalog/categories", status_code=201)
async def create_category(payload: CategoryCreate):
    inserted = supabase_run(
        supabase.table("inv_categories").insert(supabase_payload(payload)),
        "No se pudo crear la categoria"
    )
    return inserted[0] if inserted else {}


@app.get("/catalog/categories/{category_id}")
async def get_category(category_id: UUID):
    data = supabase_run(
        supabase.table("inv_categories").select("*").eq("id", str(category_id)).limit(1),
        "No se pudo obtener la categoria"
    )
    if not data:
        raise HTTPException(status_code=404, detail="Categoria no encontrada")
    return data[0]


@app.put("/catalog/categories/{category_id}")
async def update_category(category_id: UUID, payload: CategoryUpdate):
    update_data = supabase_payload(payload)
    if not update_data:
        raise HTTPException(status_code=400, detail="No hay cambios para aplicar")
    updated = supabase_run(
        supabase.table("inv_categories").update(update_data).eq("id", str(category_id)),
        "No se pudo actualizar la categoria"
    )
    if not updated:
        raise HTTPException(status_code=404, detail="Categoria no encontrada")
    return updated[0]


@app.get("/catalog/products")
async def list_products():
    data = supabase_run(
        supabase.table("inv_products").select("*").order("name"),
        "No se pudo obtener la lista de productos"
    )
    return data


@app.post("/catalog/products", status_code=201)
async def create_product(payload: ProductCreate):
    inserted = supabase_run(
        supabase.table("inv_products").insert(supabase_payload(payload)),
        "No se pudo crear el producto"
    )
    return inserted[0] if inserted else {}


@app.get("/catalog/products/{product_id}")
async def get_product(product_id: UUID):
    data = supabase_run(
        supabase.table("inv_products").select("*").eq("id", str(product_id)).limit(1),
        "No se pudo obtener el producto"
    )
    if not data:
        raise HTTPException(status_code=404, detail="Producto no encontrado")
    return data[0]


@app.put("/catalog/products/{product_id}")
async def update_product(product_id: UUID, payload: ProductUpdate):
    update_data = supabase_payload(payload)
    if not update_data:
        raise HTTPException(status_code=400, detail="No hay cambios para aplicar")
    updated = supabase_run(
        supabase.table("inv_products").update(update_data).eq("id", str(product_id)),
        "No se pudo actualizar el producto"
    )
    if not updated:
        raise HTTPException(status_code=404, detail="Producto no encontrado")
    return updated[0]


@app.get("/purchasing/suppliers")
async def list_suppliers():
    data = supabase_run(
        supabase.table("po_suppliers").select("*").order("name"),
        "No se pudo obtener la lista de proveedores"
    )
    return data


@app.post("/purchasing/suppliers", status_code=201)
async def create_supplier(payload: SupplierCreate):
    inserted = supabase_run(
        supabase.table("po_suppliers").insert(supabase_payload(payload)),
        "No se pudo crear el proveedor"
    )
    return inserted[0] if inserted else {}


@app.get("/purchasing/suppliers/{supplier_id}")
async def get_supplier(supplier_id: UUID):
    data = supabase_run(
        supabase.table("po_suppliers").select("*").eq("id", str(supplier_id)).limit(1),
        "No se pudo obtener el proveedor"
    )
    if not data:
        raise HTTPException(status_code=404, detail="Proveedor no encontrado")
    return data[0]


@app.put("/purchasing/suppliers/{supplier_id}")
async def update_supplier(supplier_id: UUID, payload: SupplierUpdate):
    update_data = supabase_payload(payload)
    if not update_data:
        raise HTTPException(status_code=400, detail="No hay cambios para aplicar")
    updated = supabase_run(
        supabase.table("po_suppliers").update(update_data).eq("id", str(supplier_id)),
        "No se pudo actualizar el proveedor"
    )
    if not updated:
        raise HTTPException(status_code=404, detail="Proveedor no encontrado")
    return updated[0]


# === Ordenes de compra ===
@app.get("/purchasing/orders")
async def list_purchase_orders(
    status: Optional[str] = None,
    search: Optional[str] = None,
    limit: int = 50
):
    query = supabase.table("po_orders").select(
        "id,order_number,status,expected_date,total_amount,currency,created_at,po_suppliers(name)"
    ).order("created_at", desc=True)
    if status:
        query = query.eq("status", status)
    if search:
        query = query.ilike("order_number", f"%{search}%")
    if limit and limit > 0:
        query = query.limit(limit)
    data = supabase_run(query, "No se pudo obtener las ordenes de compra")
    return data


def build_po_lines_payload(order_id: str, items: List[PurchaseOrderLineInput]) -> List[Dict[str, Any]]:
    """Convierte los ítems solicitados en registros para la base de datos."""
    lines_payload: List[Dict[str, Any]] = []
    for item in items:
        ensure_product_exists(item.product_id)
        line_cost = Decimal(str(item.unit_cost)).quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP)
        lines_payload.append({
            "order_id": order_id,
            "product_id": str(item.product_id),
            "quantity_ordered": float(Decimal(str(item.quantity_ordered)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)),
            "quantity_received": 0,
            "unit_cost": float(line_cost),
            "tax_rate": float(Decimal(str(item.tax_rate)).quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP)),
            "expected_receipt_date": item.expected_receipt_date.isoformat() if item.expected_receipt_date else None,
            "metadata": item.metadata or {}
        })
    return lines_payload


def calculate_po_total_from_items(items: List[PurchaseOrderLineInput]) -> float:
    total = Decimal("0")
    for item in items:
        qty = Decimal(str(item.quantity_ordered))
        cost = Decimal(str(item.unit_cost))
        total += qty * cost
    return float(total.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))


@app.post("/purchasing/orders", status_code=201)
async def create_purchase_order(payload: PurchaseOrderCreate):
    if not payload.items:
        raise HTTPException(status_code=400, detail="La orden debe contener al menos un producto")

    ensure_supplier_exists(payload.supplier_id)
    order_number = generate_po_number()
    total_amount = calculate_po_total_from_items(payload.items)

    order_data = {
        "supplier_id": str(payload.supplier_id),
        "status": "draft",
        "order_number": order_number,
        "expected_date": payload.expected_date.isoformat() if payload.expected_date else None,
        "currency": payload.currency,
        "total_amount": total_amount,
        "notes": payload.notes
    }

    inserted = supabase_run(
        supabase.table("po_orders").insert(order_data),
        "No se pudo crear la orden de compra"
    )
    order_id = inserted[0]["id"]

    lines_payload = build_po_lines_payload(order_id, payload.items)
    supabase_run(
        supabase.table("po_order_lines").insert(lines_payload),
        "No se pudieron registrar los productos de la orden"
    )

    return fetch_purchase_order(UUID(order_id))


@app.get("/purchasing/orders/{order_id}")
async def get_purchase_order(order_id: UUID):
    return fetch_purchase_order(order_id)


@app.put("/purchasing/orders/{order_id}")
async def update_purchase_order(order_id: UUID, payload: PurchaseOrderUpdate):
    order = fetch_purchase_order(order_id)
    if order.get("status") != "draft":
        raise HTTPException(status_code=400, detail="Solo se pueden editar ordenes en borrador")

    update_data: Dict[str, Any] = {}
    if payload.supplier_id is not None:
        ensure_supplier_exists(payload.supplier_id)
        update_data["supplier_id"] = str(payload.supplier_id)
    if payload.expected_date is not None:
        update_data["expected_date"] = payload.expected_date.isoformat()
    if payload.currency is not None:
        update_data["currency"] = payload.currency
    if payload.notes is not None:
        update_data["notes"] = payload.notes

    if update_data:
        supabase_run(
            supabase.table("po_orders").update(update_data).eq("id", str(order_id)),
            "No se pudo actualizar la orden de compra"
        )

    if payload.items is not None:
        if not payload.items:
            raise HTTPException(status_code=400, detail="La orden debe contener al menos un producto")
        total_amount = calculate_po_total_from_items(payload.items)
        supabase_run(
            supabase.table("po_order_lines").delete().eq("order_id", str(order_id)),
            "No se pudieron limpiar los productos anteriores"
        )
        lines_payload = build_po_lines_payload(str(order_id), payload.items)
        supabase_run(
            supabase.table("po_order_lines").insert(lines_payload),
            "No se pudieron registrar los productos actualizados"
        )
        supabase_run(
            supabase.table("po_orders").update({"total_amount": total_amount}).eq("id", str(order_id)),
            "No se pudo actualizar el total de la orden"
        )

    return fetch_purchase_order(order_id)


@app.post("/purchasing/orders/{order_id}/approve")
async def approve_purchase_order(order_id: UUID, payload: PurchaseOrderApprove):
    order = fetch_purchase_order(order_id)
    if order.get("status") != "draft":
        raise HTTPException(status_code=400, detail="Solo se pueden aprobar ordenes en borrador")

    update_data = {
        "status": "approved",
        "approved_at": datetime.utcnow().isoformat()
    }
    if payload.approved_by:
        update_data["approved_by"] = str(payload.approved_by)

    supabase_run(
        supabase.table("po_orders").update(update_data).eq("id", str(order_id)),
        "No se pudo aprobar la orden de compra"
    )

    return fetch_purchase_order(order_id)


@app.post("/purchasing/orders/{order_id}/cancel")
async def cancel_purchase_order(order_id: UUID, payload: PurchaseOrderCancel):
    order = fetch_purchase_order(order_id)
    if order.get("status") in {"closed", "cancelled"}:
        raise HTTPException(status_code=400, detail="La orden ya fue cerrada o cancelada")

    if order.get("status") not in {"draft", "approved"}:
        raise HTTPException(status_code=400, detail="No se puede cancelar una orden en proceso de recepción")

    notes = order.get("notes") or ""
    if payload.reason:
        note_line = f"Cancelado: {payload.reason}"
        notes = f"{notes}\n{note_line}" if notes else note_line

    supabase_run(
        supabase.table("po_orders").update({"status": "cancelled", "notes": notes}).eq("id", str(order_id)),
        "No se pudo cancelar la orden de compra"
    )

    return fetch_purchase_order(order_id)


@app.post("/purchasing/orders/{order_id}/receive")
async def receive_purchase_order(order_id: UUID, payload: PurchaseOrderReceive):
    if not payload.items:
        raise HTTPException(status_code=400, detail="Debe registrar al menos un producto recibido")

    order = fetch_purchase_order(order_id)
    if order.get("status") not in {"approved", "receiving"}:
        raise HTTPException(status_code=400, detail="Solo se pueden recibir ordenes aprobadas")

    lines_by_id = {UUID(line["id"]): line for line in order.get("po_order_lines", [])}
    movements: List[Dict[str, Any]] = []

    receipt_data = {
        "order_id": str(order_id),
        "reference_number": payload.reference_number,
        "received_by": str(payload.received_by) if payload.received_by else None,
        "notes": payload.notes,
        "attachments": None
    }
    receipt_inserted = supabase_run(
        supabase.table("po_receipts").insert(receipt_data),
        "No se pudo registrar la recepción"
    )
    receipt_record = receipt_inserted[0] if receipt_inserted else receipt_data

    for item in payload.items:
        line = lines_by_id.get(item.line_id)
        if not line:
            raise HTTPException(status_code=404, detail=f"Línea {item.line_id} no encontrada en la orden")

        current_received = float(line.get("quantity_received") or 0)
        ordered = float(line.get("quantity_ordered") or 0)
        new_total = current_received + item.quantity
        if new_total - ordered > 1e-6:
            raise HTTPException(
                status_code=400,
                detail=f"La cantidad recibida supera lo ordenado para el producto {line.get('product_id')}"
            )

        update_fields: Dict[str, Any] = {"quantity_received": new_total}
        if item.unit_cost is not None:
            update_fields["unit_cost"] = float(Decimal(str(item.unit_cost)).quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP))
        supabase_run(
            supabase.table("po_order_lines").update(update_fields).eq("id", str(item.line_id)),
            "No se pudo actualizar la línea de la orden"
        )

        movement_payload = MovementCreate(
            product_id=UUID(line["product_id"]),
            movement_type="purchase_receipt",
            direction=MovementDirection.IN,
            quantity=item.quantity,
            unit_cost=item.unit_cost if item.unit_cost is not None else float(line.get("unit_cost") or 0),
            reference_type="purchase_order",
            reference_id=order_id,
            notes=item.notes or payload.notes
        )
        movement_result = apply_inventory_movement(movement_payload)
        movements.append(movement_result["movement"])

    total_amount = recalculate_po_total(order_id)
    updated_order = fetch_purchase_order(order_id)
    lines = updated_order.get("po_order_lines", [])
    all_received = all(
        float(line.get("quantity_received") or 0) >= float(line.get("quantity_ordered") or 0) for line in lines
    )
    new_status = "closed" if all_received else "receiving"
    supabase_run(
        supabase.table("po_orders").update({"status": new_status, "total_amount": total_amount}).eq("id", str(order_id)),
        "No se pudo actualizar el estado de la orden"
    )

    refreshed = fetch_purchase_order(order_id)
    return {
        "order": refreshed,
        "receipt": receipt_record,
        "movements": movements
    }


# === Inventario (stock y movimientos) ===
@app.get("/inventory/stock")
async def list_stock(limit: int = 200):
    query = supabase.table("inv_stock_levels").select(
        "product_id,on_hand,allocated,available,safety_stock,last_counted_at,updated_at,inv_products(name,sku)"
    ).order("updated_at", desc=True)
    if limit and limit > 0:
        query = query.limit(limit)
    data = supabase_run(query, "No se pudo obtener el inventario del centro de distribución")
    return data


@app.get("/inventory/stock/{product_id}")
async def get_stock(product_id: UUID):
    record = get_stock_record(product_id)
    if record:
        return record
    ensure_product_exists(product_id)
    return {
        "product_id": str(product_id),
        "on_hand": 0,
        "allocated": 0,
        "available": 0,
        "safety_stock": 0
    }


@app.get("/inventory/movements")
async def list_movements(limit: int = 50, product_id: Optional[UUID] = None):
    query = supabase.table("inv_movements").select(
        "*,inv_products(name,sku)"
    ).order("occurred_at", desc=True)
    if product_id:
        query = query.eq("product_id", str(product_id))
    if limit and limit > 0:
        query = query.limit(limit)
    data = supabase_run(query, "No se pudo obtener los movimientos de inventario")
    return data


@app.post("/inventory/movements", status_code=201)
async def create_movement(payload: MovementCreate):
    return apply_inventory_movement(payload)


@app.post("/sync/woocommerce/products")
async def sync_woocommerce_products(fetch_variations: bool = True):
    products = fetch_all_woo_products()
    if not products:
        return {"processed": 0, "upserted": 0, "message": "WooCommerce no retornó productos"}

    records: List[Dict[str, Any]] = []
    for product in products:
        records.append(build_inventory_payload_from_woo(product))
        if fetch_variations and product.get("type") == "variable":
            try:
                variations = fetch_woo_variations(product.get("id"))
                for variation in variations:
                    records.append(build_inventory_payload_from_woo(product, variation))
            except HTTPException as exc:
                print(f"[WooCommerce] Error obteniendo variaciones del producto {product.get('id')}: {exc.detail}")

    deduped: Dict[str, Dict[str, Any]] = {}
    for record in records:
        deduped[record["sku"]] = record

    final_records = list(deduped.values())
    upserted = 0
    for chunk in chunk_list(final_records, size=100):
        data = supabase_run(
            supabase.table("inv_products").upsert(chunk, on_conflict="sku"),
            "No se pudieron sincronizar productos con inventario"
        )
        upserted += len(data or [])

    return {
        "processed_products": len(products),
        "records_prepared": len(records),
        "records_upserted": upserted,
        "message": "Sincronización completada"
    }


# === Webhook WooCommerce ===
@app.post("/webhooks/woocommerce")
async def webhooks_woocommerce(request: Request):
    print("🚀 Webhook WooCommerce recibido")
    raw = await request.body()
    sig = request.headers.get("x-wc-webhook-signature", "")
    topic = request.headers.get("x-wc-webhook-topic", "")

    if not valid_signature(raw, sig):
        raise HTTPException(status_code=401, detail="Invalid signature")

    # === Parsear cuerpo del webhook ===
    try:
        data = await request.json()
    except Exception:
        try:
            body_text = raw.decode("utf-8").strip()
            if body_text.startswith("{") and body_text.endswith("}"):
                data = json.loads(body_text)
            else:
                parsed = parse_qs(body_text)
                if "payload" in parsed:
                    data = json.loads(parsed["payload"][0])
                else:
                    data = {k: v[0] for k, v in parsed.items()}
        except Exception:
            traceback.print_exc()
            data = {}

    if not data or not isinstance(data, dict):
        print("⚠️ Error: cuerpo vacío o no JSON válido")
        raise HTTPException(status_code=400, detail="Invalid or empty webhook payload")

    print(f"[WooCommerce] Evento recibido: {topic}")

    order_payload: Optional[Dict[str, Any]] = None

    if topic == "order.created":
        order_payload = data
        billing = order_payload.get("billing", {})
        email = billing.get("email")
        name = f"{billing.get('first_name', '')} {billing.get('last_name', '')}".strip()
        phone = billing.get("phone")

        contact_id = upsert_contact_and_get_id(email, name, phone)
        total = float(order_payload.get("total", 0))
        status = order_payload.get("status", "created")
        woo_order_id = order_payload.get("id")

        try:
            supabase.table("orders").upsert({
                "woo_order_id": woo_order_id,
                "contact_id": contact_id,
                "total": total,
                "status": status,
                "created_at": datetime.utcnow().isoformat(),
                "raw_data": order_payload
            }).execute()
            print("[WooCommerce] Pedido guardado en tabla legacy orders")

            if status == "pending":
                supabase.table("carts").upsert({
                    "email": email,
                    "name": name,
                    "phone": phone,
                    "total": total,
                    "status": "abandoned",
                    "order_id": woo_order_id,
                    "updated_at": datetime.utcnow().isoformat()
                }).execute()
                print(f"[WooCommerce] Carrito abandonado registrado: {email}")

            elif status in ["completed", "processing"]:
                supabase.table("carts").update({
                    "status": "recovered",
                    "updated_at": datetime.utcnow().isoformat()
                }).eq("order_id", woo_order_id).execute()
                print(f"[WooCommerce] Pedido completado, carrito {woo_order_id} marcado como recuperado")

            if status in ["pending", "on-hold", "processing", "completed"] and contact_id:
                send_whatsapp_message(contact_id, name, total, phone)
                send_email_message(contact_id, name, email, total)

        except Exception:
            print("[WooCommerce] Error al procesar pedido (legacy)")
            traceback.print_exc()

    elif topic == "order.updated":
        order_payload = data

    if order_payload:
        try:
            process_woocommerce_sales_order(order_payload)
        except HTTPException as exc:
            print(f"[WooCommerce] Error HTTP al aplicar inventario: {exc.detail}")
        except Exception:
            print("[WooCommerce] Error general al sincronizar venta e inventario")
            traceback.print_exc()

    return JSONResponse({"status": "ok", "topic": topic})



# === Worker: CRM Nurturer (WhatsApp + Email) ===
def send_whatsapp_message(contact_id, name, total, phone):
    """Envia confirmación por WhatsApp."""
    text = f"👋 Hola {name.split()[0]}! Gracias por tu compra en Noga Marks 🛍️. " \
           f"Tu pedido por S/. {total:.2f} está siendo procesado. Te avisaremos apenas se despache. 💌"

    status = "pending"
    try:
        client = TwilioClient(TWILIO_SID, TWILIO_TOKEN)
        to_number = f"whatsapp:+{phone.replace('+', '')}" if phone else TWILIO_TO_DEFAULT
        msg = client.messages.create(from_=TWILIO_FROM, body=text, to=to_number)
        print(f"💬 WhatsApp enviado a {to_number} → SID: {msg.sid}")
        status = "sent"
    except Exception:
        print("⚠️ Error al enviar WhatsApp:")
        traceback.print_exc()
        status = "failed"

    supabase.table("messages").insert({
        "contact_id": contact_id,
        "channel": "whatsapp",
        "message": text,
        "status": status,
        "created_at": datetime.utcnow().isoformat()
    }).execute()


def send_email_message(contact_id, name, email, total):
    """Envia correo de confirmación de compra."""
    if not email:
        print("⚠️ No se puede enviar correo: falta email")
        return

    subject = "Confirmación de tu compra en Noga Marks"
    body = f"""
    <h2>¡Gracias por tu compra, {name.split()[0]}!</h2>
    <p>Tu pedido por <strong>S/. {total:.2f}</strong> está siendo procesado.</p>
    <p>Te avisaremos apenas esté en camino. 💌</p>
    <p>— El equipo de Noga Marks</p>
    """

    msg = MIMEMultipart()
    msg["From"] = os.getenv("EMAIL_FROM")
    msg["To"] = email
    msg["Subject"] = subject
    msg.attach(MIMEText(body, "html"))

    try:
        server = smtplib.SMTP(os.getenv("EMAIL_HOST"), int(os.getenv("EMAIL_PORT", 587)))
        server.starttls()
        server.login(os.getenv("EMAIL_USER"), os.getenv("EMAIL_PASS"))
        server.send_message(msg)
        server.quit()
        print(f"📧 Correo enviado a {email}")

        supabase.table("messages").insert({
            "contact_id": contact_id,
            "channel": "email",
            "message": subject,
            "status": "sent",
            "created_at": datetime.utcnow().isoformat()
        }).execute()
    except Exception:
        print("⚠️ Error al enviar correo:")
        traceback.print_exc()

@app.post("/webhooks/cart")
async def webhook_cart(request: Request):
    """Recibe eventos de WooCommerce sobre carritos."""
    print("🛒 Webhook carrito recibido")
    raw = await request.body()
    try:
        data = await request.json()
    except:
        data = {}

    if not data:
        return JSONResponse({"status": "error", "msg": "empty payload"}, status_code=400)

    billing = data.get("billing", {})
    email = billing.get("email")
    name = f"{billing.get('first_name', '')} {billing.get('last_name', '')}".strip()
    phone = billing.get("phone")
    total = data.get("total", 0)
    cart_items = data.get("line_items", [])

    if not email:
        return JSONResponse({"status": "ignored", "msg": "no email"})

    supabase.table("carts").upsert({
        "email": email,
        "phone": phone,
        "name": name,
        "cart_items": cart_items,
        "total": total,
        "status": "abandoned"
    }).execute()

    print(f"🟡 Carrito abandonado registrado: {email}")
    return {"status": "ok"}

@app.on_event("startup")
@repeat_every(seconds=7200)  # cada 2 horas
def process_abandoned_carts():
    print("🔁 Revisión de carritos abandonados...")

    res = supabase.table("carts").select("*").eq("status", "abandoned").execute()
    if not res.data:
        print("No hay carritos abandonados pendientes.")
        return

    for cart in res.data:
        email = cart.get("email")
        name = cart.get("name")
        phone = cart.get("phone")
        total = cart.get("total", 0)
        cart_id = cart.get("id")

        message = f"👋 Hola {name.split()[0]}! Notamos que dejaste algunos artículos en tu carrito 🛍️ por S/. {total:.2f}. Usa el código **AUREA10** para obtener 10% de descuento si completas tu compra hoy ✨"

        # WhatsApp
        try:
            client = TwilioClient(TWILIO_SID, TWILIO_TOKEN)
            to_number = f"whatsapp:+{phone.replace('+', '')}" if phone else TWILIO_TO_DEFAULT
            msg = client.messages.create(from_=TWILIO_FROM, body=message, to=to_number)
            print(f"💬 Recordatorio WhatsApp enviado a {to_number}")
        except Exception as e:
            print("⚠️ Error al enviar WhatsApp:", e)

        # Email
        try:
            msg = MIMEMultipart()
            msg["From"] = os.getenv("EMAIL_FROM")
            msg["To"] = email
            msg["Subject"] = "Completa tu compra en Aurea Move ✨"
            body = f"""
            <h3>Hola {name.split()[0]},</h3>
            <p>Tu carrito te está esperando 🛍️</p>
            <p>Usa el código <strong>AUREA10</strong> y obtén 10% de descuento si compras hoy mismo.</p>
            <p><a href="https://aureamove.com/cart" style="color:#000;">Volver al carrito</a></p>
            """
            msg.attach(MIMEText(body, "html"))
            server = smtplib.SMTP(os.getenv("EMAIL_HOST"), int(os.getenv("EMAIL_PORT", 587)))
            server.starttls()
            server.login(os.getenv("EMAIL_USER"), os.getenv("EMAIL_PASS"))
            server.send_message(msg)
            server.quit()
            print(f"📧 Email recordatorio enviado a {email}")
        except Exception as e:
            print("⚠️ Error al enviar email:", e)

        # Actualizar estado
        supabase.table("carts").update({"status": "notified"}).eq("id", cart_id).execute()

    print("✅ Worker de carritos abandonados completado.")

# === Versión manual del worker (sin async) ===
def process_abandoned_carts_manual():
    print("🔁 Ejecución manual del worker de carritos abandonados...")

        # --- Sincronizar pedidos "on hold" como carritos abandonados ---
    try:
        pending_orders = supabase.table("orders").select("*").eq("status", "on-hold").execute()
        for order in pending_orders.data:
            contact_id = order.get("contact_id")
            woo_order_id = order.get("woo_order_id")
            total = order.get("total", 0)
            raw_data = order.get("raw_data", {})
            billing = raw_data.get("billing", {})
            email = billing.get("email")
            name = f"{billing.get('first_name', '')} {billing.get('last_name', '')}".strip()
            phone = billing.get("phone")

            if email:
                supabase.table("carts").upsert({
                    "email": email,
                    "phone": phone,
                    "name": name,
                    "total": total,
                    "status": "abandoned",
                    "order_id": woo_order_id,
                    "created_at": datetime.utcnow().isoformat()
                }).execute()
                print(f"🟡 Pedido 'on hold' sincronizado como carrito: {email}")
    except Exception as e:
        print("⚠️ Error al sincronizar pedidos 'on hold':", e)


    try:
        res = supabase.table("carts").select("*").eq("status", "abandoned").execute()
        if not res.data:
            print("No hay carritos abandonados pendientes.")
            return

        for cart in res.data:
            email = cart.get("email")
            name = cart.get("name")
            phone = cart.get("phone")
            total = cart.get("total", 0)
            cart_id = cart.get("id")

            message = f"👋 Hola {name.split()[0]}! Notamos que dejaste algunos artículos en tu carrito 🛍️ por S/. {total:.2f}. Usa el código **AUREA10** para obtener 10% de descuento si completas tu compra hoy ✨"

            # Enviar WhatsApp
            try:
                client = TwilioClient(TWILIO_SID, TWILIO_TOKEN)
                to_number = f"whatsapp:+{phone.replace('+', '')}" if phone else TWILIO_TO_DEFAULT
                msg = client.messages.create(from_=TWILIO_FROM, body=message, to=to_number)
                print(f"💬 Recordatorio WhatsApp enviado a {to_number}")
            except Exception as e:
                print("⚠️ Error al enviar WhatsApp:", e)

            # Enviar Email
            try:
                msg = MIMEMultipart()
                msg["From"] = os.getenv("EMAIL_FROM")
                msg["To"] = email
                msg["Subject"] = "Completa tu compra en Aurea Move ✨"
                body = f"""
                <h3>Hola {name.split()[0]},</h3>
                <p>Tu carrito te está esperando 🛍️</p>
                <p>Usa el código <strong>AUREA10</strong> y obtén 10% de descuento si compras hoy mismo.</p>
                <p><a href="https://aureamove.com/cart" style="color:#000;">Volver al carrito</a></p>
                """
                msg.attach(MIMEText(body, "html"))
                server = smtplib.SMTP(os.getenv("EMAIL_HOST"), int(os.getenv("EMAIL_PORT", 587)))
                server.starttls()
                server.login(os.getenv("EMAIL_USER"), os.getenv("EMAIL_PASS"))
                server.send_message(msg)
                server.quit()
                print(f"📧 Email recordatorio enviado a {email}")
            except Exception as e:
                print("⚠️ Error al enviar email:", e)

            # Actualizar estado
            supabase.table("carts").update({"status": "notified"}).eq("id", cart_id).execute()

        print("✅ Worker manual completado correctamente.")
    except Exception as e:
        print("❌ Error general en worker manual:", e)
