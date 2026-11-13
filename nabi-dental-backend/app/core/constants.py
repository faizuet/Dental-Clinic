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
    PATIENT = "patient"
    CLINIC_EXPENSE_CATEGORY = "clinic_expense_category"
    CLINIC_EXPENSE = "clinic_expense"
    HOME_EXPENSE_CATEGORY = "home_expense_category"
    HOME_EXPENSE = "home_expense"
    HOME_BUDGET = "home_budget"


class SyncOperation(StrEnum):
    CREATE = "create"
    UPDATE = "update"
    DELETE = "delete"


class SyncItemStatus(StrEnum):
    APPLIED = "applied"
    CONFLICT = "conflict"
    FAILED = "failed"
    IDEMPOTENT = "applied"


SEED_CLINIC_TREATMENTS = [
    "Check Up / Consultation",
    "Simple Extraction",
    "Surgical Extraction",
    "Root Canal Treatment (RCT)",
    "Obturation (RCT)",
    "Temporary Filling",
    "Permanent Filling",
    "Composite Filling",
    "Scaling",
    "Porcelain Bridge",
    "Zirconia Crown",
    "Braces Fresh",
    "Braces Visits",
    "Braces Retainer",
    "Dental Gems",
]

SEED_TREATMENTS: dict[str, list[str]] = {
    "Dental Treatments": SEED_CLINIC_TREATMENTS,
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

SEED_HOME_EXPENSE_CATEGORIES = [
    "Fresh Vegetables",
    "Fruits",
    "Beef / Mutton",
    "Chicken",
    "Eggs",
    "Daalain",
    "Milk / Yogurt",
    "Butter Cheese",
    "Bread Rusk",
    "Honey / Jam",
    "Frozen Items",
    "Atta White",
    "Chawal",
    "Sugar",
    "Cooking Oil",
    "Tea",
    "Masaly cooking",
    "Ketchup, Mayo, Sauces",
    "Dry Fruits",
    "Cold drinks",
    "Shampoo, Conditioners",
    "Soap Body wash",
    "Face wash",
    "Toothpaste toothbrush",
    "Hair Oil",
    "Bathroom Accessories",
    "Air freshener",
    "Tissue",
    "Washing Surf",
    "Harpic",
    "Pheyl",
    "Mortien",
    "Mosquito spray",
    "Hygiene Items",
]
