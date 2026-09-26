from typing import Any


TOOTH_NAMES: dict[str, str] = {
    "11": "Upper Right Central Incisor",
    "12": "Upper Right Lateral Incisor",
    "13": "Upper Right Canine",
    "14": "Upper Right First Premolar",
    "15": "Upper Right Second Premolar",
    "16": "Upper Right First Molar",
    "17": "Upper Right Second Molar",
    "18": "Upper Right Third Molar",
    "21": "Upper Left Central Incisor",
    "22": "Upper Left Lateral Incisor",
    "23": "Upper Left Canine",
    "24": "Upper Left First Premolar",
    "25": "Upper Left Second Premolar",
    "26": "Upper Left First Molar",
    "27": "Upper Left Second Molar",
    "28": "Upper Left Third Molar",
    "31": "Lower Left Central Incisor",
    "32": "Lower Left Lateral Incisor",
    "33": "Lower Left Canine",
    "34": "Lower Left First Premolar",
    "35": "Lower Left Second Premolar",
    "36": "Lower Left First Molar",
    "37": "Lower Left Second Molar",
    "38": "Lower Left Third Molar",
    "41": "Lower Right Central Incisor",
    "42": "Lower Right Lateral Incisor",
    "43": "Lower Right Canine",
    "44": "Lower Right First Premolar",
    "45": "Lower Right Second Premolar",
    "46": "Lower Right First Molar",
    "47": "Lower Right Second Molar",
    "48": "Lower Right Third Molar",
}


def tooth_name_for(number: str | None) -> str | None:
    if not number:
        return None
    return TOOTH_NAMES.get(str(number).strip())


def _as_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    text = str(value).strip()
    return [text] if text else []


def tooth_label(details: dict[str, Any] | None) -> str | None:
    data = details or {}
    numbers = _as_list(data.get("tooth_numbers") or data.get("tooth_number"))
    names = _as_list(data.get("tooth_names") or data.get("tooth_name"))
    if not numbers and not names:
        return None
    if numbers and names and len(numbers) == len(names):
        return ", ".join(f"#{number} {name}" for number, name in zip(numbers, names, strict=False))
    if numbers:
        return ", ".join(f"#{number}" for number in numbers)
    return ", ".join(names)


def family_label(name: str | None, category_name: str | None = None) -> str:
    n = (name or "").lower()
    c = (category_name or "").lower()
    if "rct" in n or "root canal" in n:
        return "RCT"
    if "prosthetic" in c or any(token in n for token in ("crown", "bridge", "denture", "implant")):
        return "Prosthetic"
    if "perio" in c or "scaling" in n:
        return "Periodontal"
    return "Other"


def resolved_sub_treatment(
    *,
    sub_treatment: str | None = None,
    details: dict[str, Any] | None = None,
    treatment_name: str | None = None,
) -> str | None:
    if sub_treatment and str(sub_treatment).strip():
        return str(sub_treatment).strip()
    nested = (details or {}).get("sub_treatment")
    if nested and str(nested).strip():
        return str(nested).strip()
    if treatment_name and str(treatment_name).strip():
        return str(treatment_name).strip()
    return None


def clinical_summary(details: dict[str, Any] | None, sub_treatment: str | None = None) -> str | None:
    data = details or {}
    parts: list[str] = []
    if sub_treatment and sub_treatment.strip():
        parts.append(sub_treatment.strip())
    tooth = tooth_label(data)
    if tooth:
        parts.append(tooth)
    if data.get("canals"):
        parts.append(f"{data['canals']} canals")
    if data.get("length_mm"):
        parts.append(f"{data['length_mm']} mm")
    if data.get("material"):
        parts.append(str(data["material"]))
    if data.get("units"):
        parts.append(f"{data['units']} units")
    arch = data.get("arch") or data.get("denture_type")
    if arch:
        parts.append(str(arch).replace("_", " ").title())
    if data.get("scope"):
        parts.append(str(data["scope"]).replace("_", " ").title())
    if data.get("teeth_count"):
        parts.append(f"{data['teeth_count']} teeth")
    if data.get("partial_details"):
        parts.append(str(data["partial_details"]))
    return ", ".join(parts) if parts else None
