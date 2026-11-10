from __future__ import annotations

from PIL import Image


def reject_non_dental_image(image: Image.Image) -> str | None:
    """Return an error if the photo is clearly not a dental clinical image.

    Accepts radiographs (low colour, clinical contrast) and intraoral photos
    (tooth-like whites and gingival pinks). Rejects obvious outdoor scenes
    and personal photos without oral content. Lighting, angle, and quality
    are not used as rejection reasons.
    """
    sample = image.convert("RGB")
    sample.thumbnail((96, 96))
    pixels = list(sample.getdata())
    count = len(pixels)
    if count == 0:
        return "That file is not a valid image."

    gray = tooth = gingival = sky = green = skin = 0
    luminances: list[float] = []
    for red, green_v, blue in pixels:
        r, g, b = red / 255.0, green_v / 255.0, blue / 255.0
        mx, mn = max(r, g, b), min(r, g, b)
        diff = mx - mn
        saturation = 0.0 if mx == 0 else diff / mx
        value = mx
        luminance = 0.299 * r + 0.587 * g + 0.114 * b
        luminances.append(luminance)
        if saturation < 0.12:
            gray += 1
        hue = _hue(r, g, b, mx, diff)
        if value > 0.72 and saturation < 0.22 and luminance > 0.62:
            tooth += 1
        if saturation >= 0.15 and 0.25 <= value <= 0.92 and (hue <= 25 or hue >= 335):
            gingival += 1
        if 190 <= hue <= 245 and saturation > 0.25 and value > 0.35:
            sky += 1
        if 70 <= hue <= 160 and saturation > 0.28 and value > 0.2:
            green += 1
        if 12 <= hue <= 42 and 0.18 <= saturation <= 0.62 and 0.28 <= value <= 0.9:
            skin += 1

    gray_ratio = gray / count
    tooth_ratio = tooth / count
    gingival_ratio = gingival / count
    sky_ratio = sky / count
    green_ratio = green / count
    skin_ratio = skin / count
    mean_l = sum(luminances) / count
    variance = sum((item - mean_l) ** 2 for item in luminances) / count
    contrast = variance ** 0.5

    looks_like_xray = gray_ratio >= 0.55 and 0.06 <= mean_l <= 0.88
    looks_intraoral = tooth_ratio >= 0.02 and gingival_ratio >= 0.012
    looks_teeth_closeup = tooth_ratio >= 0.07
    looks_oral_soft_tissue = gingival_ratio >= 0.07
    looks_clinical = looks_like_xray or looks_intraoral or looks_teeth_closeup or looks_oral_soft_tissue

    if sky_ratio >= 0.18 and green_ratio >= 0.12 and not looks_clinical:
        return "This does not look like a dental X-ray or intraoral photo. Choose a clinical image."
    if sky_ratio >= 0.3 and not looks_clinical:
        return "This does not look like a dental X-ray or intraoral photo. Choose a clinical image."
    if green_ratio >= 0.38 and tooth_ratio < 0.02 and not looks_like_xray:
        return "This does not look like a dental X-ray or intraoral photo. Choose a clinical image."
    if skin_ratio >= 0.38 and tooth_ratio < 0.015 and gingival_ratio < 0.02 and not looks_like_xray:
        return "This looks like a personal photo rather than a dental image. Choose an X-ray or intraoral photo."
    if contrast < 0.03 and gray_ratio < 0.5 and not looks_clinical:
        return "This does not look like a dental X-ray or intraoral photo. Choose a clinical image."
    if not looks_clinical:
        return "This does not look like a dental X-ray or intraoral photo. Choose a clinical image."
    return None


def _hue(r: float, g: float, b: float, mx: float, diff: float) -> float:
    if diff == 0:
        return 0.0
    if mx == r:
        hue = (60 * ((g - b) / diff) + 360) % 360
    elif mx == g:
        hue = (60 * ((b - r) / diff) + 120) % 360
    else:
        hue = (60 * ((r - g) / diff) + 240) % 360
    return hue
