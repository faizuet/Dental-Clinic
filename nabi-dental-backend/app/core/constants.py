from enum import StrEnum


class ErrorCode(StrEnum):
    VALIDATION_ERROR = "VALIDATION_ERROR"
    UNAUTHORIZED = "UNAUTHORIZED"
    FORBIDDEN = "FORBIDDEN"
    NOT_FOUND = "NOT_FOUND"
    CONFLICT = "CONFLICT"
    VERSION_CONFLICT = "VERSION_CONFLICT"
    RATE_LIMITED = "RATE_LIMITED"
    INACTIVE_ACCOUNT = "INACTIVE_ACCOUNT"
    CATALOG_IN_USE = "CATALOG_IN_USE"
    INTERNAL_ERROR = "INTERNAL_ERROR"
    DEPENDENCY_UNAVAILABLE = "DEPENDENCY_UNAVAILABLE"


class UserRole(StrEnum):
    OWNER = "owner"
    ADMIN = "admin"
    STAFF = "staff"


class Period(StrEnum):
    DAILY = "daily"
    MONTHLY = "monthly"
    YEARLY = "yearly"
    CUSTOM = "custom"


class GroupBy(StrEnum):
    DAY = "day"
    WEEK = "week"
    YEAR = "year"
    MONTH = "month"


class ExportFormat(StrEnum):
    PDF = "pdf"
    XLSX = "xlsx"


class SyncEntity(StrEnum):
    TREATMENT_CATEGORY = "treatment_category"
    TREATMENT = "treatment"
    TREATMENT_TRANSACTION = "treatment_transaction"
    CLINIC_EXPENSE_CATEGORY = "clinic_expense_category"
    CLINIC_EXPENSE = "clinic_expense"
    HOME_EXPENSE_CATEGORY = "home_expense_category"
    HOME_EXPENSE = "home_expense"
    HOME_BUDGET = "home_budget"
    CONSTRUCTION_MATERIAL_CATEGORY = "construction_material_category"
    CONSTRUCTION_MATERIAL = "construction_material"
    CONSTRUCTION_PURCHASE = "construction_purchase"


class SyncOperation(StrEnum):
    CREATE = "create"
    UPDATE = "update"
    DELETE = "delete"


class SyncItemStatus(StrEnum):
    APPLIED = "applied"
    CONFLICT = "conflict"
    FAILED = "failed"
    IDEMPOTENT = "applied"


SEED_TREATMENTS: dict[str, list[str]] = {
    "Basic": ["Consultation", "Scaling and Polishing", "Dental Filling"],
    "Extraction": ["Tooth Extraction"],
    "Endodontics": ["RCT", "Pulpotomy", "Apicoectomy"],
    "Prosthetics": ["Crown", "Dental Bridge", "Dentures", "Dental Implant"],
    "Orthodontics": ["Braces", "Clear Aligners"],
    "Cosmetic": ["Veneers", "Teeth Whitening"],
    "Restorative": ["Inlay or Onlay"],
    "Periodontal": ["Gingivectomy", "Frenectomy"],
    "Protective": ["Night Guard", "Sports Guard"],
    "Diagnostic": ["X Ray", "Panoramic X Ray"],
    "Emergency": ["Emergency Treatment"],
}

SEED_CLINIC_EXPENSE_CATEGORIES = [
    "Lab Charges",
    "Materials",
    "Equipment",
    "Salaries",
    "Rent",
    "Utilities",
    "Other",
]

SEED_CONSTRUCTION_MATERIALS: dict[str, list[tuple[str, str]]] = {
    "Structure": [
        ("Cement", "bag"),
        ("Bricks / Blocks", "piece"),
        ("Sand", "cft"),
        ("Crush / Aggregate", "cft"),
        ("Steel / Rebar", "kg"),
        ("Concrete", "cft"),
        ("Stone", "cft"),
        ("Roofing materials", "sqft"),
        ("Waterproofing materials", "kg"),
    ],
    "Woodwork": [
        ("Wood / Timber", "cft"),
        ("Doors", "piece"),
        ("Windows", "piece"),
        ("Cabinets", "piece"),
        ("Frames", "piece"),
    ],
    "Electrical": [
        ("Electrical wires and cables", "meter"),
        ("Switches and sockets", "piece"),
        ("Lights and fixtures", "piece"),
    ],
    "Plumbing": [
        ("Pipes", "meter"),
        ("Plumbing fittings", "piece"),
        ("Water tanks", "piece"),
    ],
    "Finishing": [
        ("Tiles", "sqft"),
        ("Marble / Granite", "sqft"),
        ("Paint", "liter"),
        ("Putty / Plaster materials", "kg"),
        ("Glass", "sqft"),
    ],
    "Sanitary": [
        ("Sanitary items", "piece"),
    ],
    "Other": [
        ("Hardware items", "piece"),
        ("Nails, screws, and fasteners", "kg"),
        ("Other construction materials", "piece"),
    ],
}

SEED_HOME_EXPENSE_CATEGORIES = [
    "Groceries",
    "Utilities",
    "Rent",
    "Transport",
    "Education",
    "Medical",
    "Entertainment",
    "Shopping",
    "Other",
]
