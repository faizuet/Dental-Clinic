from decimal import Decimal

from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.constants import (
    SEED_CLINIC_EXPENSE_CATEGORIES,
    SEED_CLINIC_TREATMENTS,
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

    official = {name.lower() for name in SEED_CLINIC_TREATMENTS}
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
            existing = treatments_by_name.get(treatment_name.lower())
            if existing is not None:
                existing.display_order = treatment_order
                existing.category_id = category.id
                existing.is_active = True
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

    for treatment in treatments_by_name.values():
        if treatment.name.lower() not in official:
            treatment.is_active = False


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
    existing = (
        await session.execute(
            select(HomeExpenseCategory).where(
                HomeExpenseCategory.user_id == user.id,
                HomeExpenseCategory.deleted_at.is_(None),
            )
        )
    ).scalars().all()
    by_name = {item.name.strip().lower(): item for item in existing}
    official = {name.lower() for name in SEED_HOME_EXPENSE_CATEGORIES}
    used_ids = set(
        (
            await session.execute(
                select(HomeExpense.category_id).where(
                    HomeExpense.user_id == user.id,
                    HomeExpense.deleted_at.is_(None),
                )
            )
        ).scalars()
    )

    for order, name in enumerate(SEED_HOME_EXPENSE_CATEGORIES):
        record = by_name.get(name.lower())
        if record is None:
            record = HomeExpenseCategory(
                user_id=user.id,
                name=name,
                display_order=order,
                is_active=True,
            )
            session.add(record)
            by_name[name.lower()] = record
            continue
        record.display_order = order
        record.is_active = True

    for record in existing:
        if record.name.strip().lower() in official:
            continue
        if record.id in used_ids:
            record.is_active = False
            continue
        record.soft_delete()


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
