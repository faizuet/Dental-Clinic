from fastapi import APIRouter

from app.api.v1.endpoints import (
    auth,
    clinic_expense_categories,
    clinic_expenses,
    construction,
    dashboard,
    home_budgets,
    home_expense_categories,
    home_expenses,
    patients,
    reports,
    settings,
    sync,
    treatment_categories,
    treatment_transactions,
    treatments,
)

api_router = APIRouter()
v1_routers = [
    auth.router,
    treatment_categories.router,
    treatments.router,
    treatment_transactions.router,
    patients.router,
    clinic_expense_categories.router,
    clinic_expenses.router,
    home_expense_categories.router,
    home_expenses.router,
    home_budgets.router,
    construction.categories_router,
    construction.materials_router,
    construction.purchases_router,
    dashboard.router,
    reports.router,
    settings.router,
    sync.router,
]
for router in v1_routers:
    api_router.include_router(router)
