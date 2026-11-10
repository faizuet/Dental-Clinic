from PIL import Image, ImageDraw

from app.utils.dental_image import reject_non_dental_image


def _xray() -> Image.Image:
    image = Image.new("L", (180, 180), color=16)
    ImageDraw.Draw(image).ellipse((25, 20, 155, 160), fill=175)
    return image


def _intraoral() -> Image.Image:
    image = Image.new("RGB", (180, 180), color=(176, 68, 78))
    for y in range(50, 130):
        for x in range(40, 140):
            image.putpixel((x, y), (246, 242, 232))
    return image


def _landscape() -> Image.Image:
    image = Image.new("RGB", (180, 180), color=(80, 165, 235))
    for y in range(90, 180):
        for x in range(180):
            image.putpixel((x, y), (46, 148, 58))
    return image


def test_accepts_radiograph_and_intraoral():
    assert reject_non_dental_image(_xray()) is None
    assert reject_non_dental_image(_intraoral()) is None


def test_rejects_landscape():
    message = reject_non_dental_image(_landscape())
    assert message is not None
    assert "dental" in message.lower()
