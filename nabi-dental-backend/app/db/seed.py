from decimal import Decimal

from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.constants import (
    SEED_CLINIC_EXPENSE_CATEGORIES,
    SEED_CONSTRUCTION_MATERIALS,
    SEED_HOME_EXPENSE_CATEGORIES,
    SEED_TREATMENTS,
    UserRole,
)
from app.core.logging import logger
from app.core.security import hash_password
from app.db.session import SessionLocal
from app.models import (
    Clinic,
    ClinicExpense,
    ClinicExpenseCategory,
    ConstructionMaterial,
    ConstructionMaterialCategory,
    ConstructionPurchase,
    HomeExpense,
    HomeExpenseCategory,
    Treatment,
    TreatmentCategory,
    TreatmentTransaction,
    User,
)


async def seed_database(session: AsyncSession) -> None:
    clinic = await _get_or_create_clinic(session)
    owner = await _get_or_create_owner(session, clinic)
    await _seed_treatments(session, clinic)
    await _seed_clinic_expense_categories(session, clinic)
    await _seed_home_expense_categories(session, owner)
    await seed_construction_catalog(session, owner)
    await _dedupe_clinic_catalogs(session, clinic, owner)
    await session.commit()
    logger.info("Seed completed", extra={"clinic_id": str(clinic.id), "user_id": str(owner.id)})


async def _get_or_create_clinic(session: AsyncSession) -> Clinic:
    result = await session.execute(select(Clinic).where(Clinic.name == settings.DEFAULT_CLINIC_NAME))
    clinic = result.scalar_one_or_none()
    if clinic:
        return clinic
    clinic = Clinic(
        name=settings.DEFAULT_CLINIC_NAME,
        currency=settings.DEFAULT_CURRENCY,
        timezone=settings.DEFAULT_TIMEZONE,
    )
    session.add(clinic)
    await session.flush()
    return clinic


async def _get_or_create_owner(session: AsyncSession, clinic: Clinic) -> User:
    email = settings.OWNER_EMAIL.strip().lower()
    result = await session.execute(select(User).where(func.lower(User.email) == email))
    user = result.scalar_one_or_none()
    if user:
        return user
    user = User(
        clinic_id=clinic.id,
        full_name=settings.OWNER_FULL_NAME,
        email=email,
        password_hash=hash_password(settings.OWNER_PASSWORD),
        role=UserRole.OWNER,
        default_home_budget=Decimal(settings.DEFAULT_HOME_BUDGET),
        is_active=True,
    )
    session.add(user)
    await session.flush()
    return user


async def _seed_treatments(session: AsyncSession, clinic: Clinic) -> None:
    existing_categories = await session.execute(
        select(TreatmentCategory).where(
            TreatmentCategory.clinic_id == clinic.id,
            TreatmentCategory.deleted_at.is_(None),
        )
    )
    categories_by_name = {item.name.lower(): item for item in existing_categories.scalars()}
    existing_treatments = await session.execute(
        select(Treatment).where(Treatment.clinic_id == clinic.id, Treatment.deleted_at.is_(None))
    )
    treatments_by_name = {item.name.lower(): item for item in existing_treatments.scalars()}

    for category_order, (category_name, treatment_names) in enumerate(SEED_TREATMENTS.items()):
        category = categories_by_name.get(category_name.lower())
        if category is None:
            category = TreatmentCategory(
                clinic_id=clinic.id,
                name=category_name,
                display_order=category_order,
                is_active=True,
            )
            session.add(category)
            await session.flush()
            categories_by_name[category_name.lower()] = category
        for treatment_order, treatment_name in enumerate(treatment_names):
            if treatment_name.lower() in treatments_by_name:
                continue
            treatment = Treatment(
                clinic_id=clinic.id,
                category_id=category.id,
                name=treatment_name,
                display_order=treatment_order,
                is_active=True,
            )
            session.add(treatment)
            treatments_by_name[treatment_name.lower()] = treatment


async def _seed_clinic_expense_categories(session: AsyncSession, clinic: Clinic) -> None:
    existing = await session.execute(
        select(ClinicExpenseCategory).where(
            ClinicExpenseCategory.clinic_id == clinic.id,
            ClinicExpenseCategory.deleted_at.is_(None),
        )
    )
    present = {item.name.lower() for item in existing.scalars()}
    for order, name in enumerate(SEED_CLINIC_EXPENSE_CATEGORIES):
        if name.lower() in present:
            continue
        session.add(
            ClinicExpenseCategory(
                clinic_id=clinic.id,
                name=name,
                display_order=order,
                is_active=True,
            )
        )


async def _seed_home_expense_categories(session: AsyncSession, user: User) -> None:
    existing = await session.execute(
        select(HomeExpenseCategory).where(
            HomeExpenseCategory.user_id == user.id,
            HomeExpenseCategory.deleted_at.is_(None),
        )
    )
    present = {item.name.lower() for item in existing.scalars()}
    for order, name in enumerate(SEED_HOME_EXPENSE_CATEGORIES):
        if name.lower() in present:
            continue
        session.add(
            HomeExpenseCategory(
                user_id=user.id,
                name=name,
                display_order=order,
                is_active=True,
            )
        )


async def seed_construction_catalog(session: AsyncSession, user: User) -> None:
    existing_categories = await session.execute(
        select(ConstructionMaterialCategory).where(
            ConstructionMaterialCategory.user_id == user.id,
            ConstructionMaterialCategory.deleted_at.is_(None),
        )
    )
    categories = {item.name.lower(): item for item in existing_categories.scalars()}
    existing_materials = await session.execute(
        select(ConstructionMaterial).where(
            ConstructionMaterial.user_id == user.id,
            ConstructionMaterial.deleted_at.is_(None),
        )
    )
    present_materials = {item.name.lower() for item in existing_materials.scalars()}

    for category_order, (category_name, materials) in enumerate(SEED_CONSTRUCTION_MATERIALS.items()):
        category = categories.get(category_name.lower())
        if category is None:
            category = ConstructionMaterialCategory(
                user_id=user.id,
                name=category_name,
                display_order=category_order,
                is_active=True,
            )
            session.add(category)
            await session.flush()
            categories[category_name.lower()] = category
        for material_order, (material_name, unit) in enumerate(materials):
            if material_name.lower() in present_materials:
                continue
            session.add(
                ConstructionMaterial(
                    user_id=user.id,
                    category_id=category.id,
                    name=material_name,
                    unit=unit,
                    display_order=material_order,
                    is_active=True,
                )
            )
            present_materials.add(material_name.lower())


async def _dedupe_clinic_catalogs(session: AsyncSession, clinic: Clinic, owner: User) -> None:
    await _dedupe_by_name(
        session,
        TreatmentCategory,
        TreatmentCategory.clinic_id == clinic.id,
        child_model=Treatment,
        child_fk="category_id",
    )
    await _dedupe_by_name(
        session,
        Treatment,
        Treatment.clinic_id == clinic.id,
        child_model=TreatmentTransaction,
        child_fk="treatment_id",
    )
    await _dedupe_by_name(
        session,
        ClinicExpenseCategory,
        ClinicExpenseCategory.clinic_id == clinic.id,
        child_model=ClinicExpense,
        child_fk="category_id",
    )
    await _dedupe_by_name(
        session,
        HomeExpenseCategory,
        HomeExpenseCategory.user_id == owner.id,
        child_model=HomeExpense,
        child_fk="category_id",
    )
    await _dedupe_by_name(
        session,
        ConstructionMaterialCategory,
        ConstructionMaterialCategory.user_id == owner.id,
        child_model=ConstructionMaterial,
        child_fk="category_id",
    )
    await _dedupe_by_name(
        session,
        ConstructionMaterial,
        ConstructionMaterial.user_id == owner.id,
        child_model=ConstructionPurchase,
        child_fk="material_id",
    )


async def _dedupe_by_name(session, model, scope, *, child_model, child_fk: str) -> None:
    rows = (await session.execute(select(model).where(scope, model.deleted_at.is_(None)))).scalars().all()
    groups: dict[str, list] = {}
    for row in rows:
        groups.setdefault(row.name.strip().lower(), []).append(row)
    for items in groups.values():
        if len(items) < 2:
            continue
        items.sort(key=lambda item: (item.created_at, str(item.id)))
        keep = items[0]
        for extra in items[1:]:
            await session.execute(
                update(child_model).where(getattr(child_model, child_fk) == extra.id).values(**{child_fk: keep.id})
            )
            extra.soft_delete()


async def main() -> None:
    async with SessionLocal() as session:
        await seed_database(session)


if __name__ == "__main__":
    import asyncio

    asyncio.run(main())
