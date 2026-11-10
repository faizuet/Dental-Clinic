from pathlib import Path

from PIL import Image as PILImage

from app.exports.pdf import _fit_image, _treatment_images


def test_fit_image_stays_inside_the_frame():
    width, height = _fit_image(4000, 2250, 190, 128)
    assert width <= 190.01
    assert height <= 128.01
    assert abs((width / height) - (4000 / 2250)) < 0.01


def test_treatment_images_use_framed_blocks(tmp_path: Path):
    photo = tmp_path / "before.png"
    PILImage.new("RGB", (1600, 900), color=(40, 80, 120)).save(photo, format="PNG")
    blocks = _treatment_images([("before", str(photo))])
    assert blocks
    assert blocks[0].text == "X-ray images"
    grid = blocks[1]
    frame = grid._cellvalues[0][0]
    image = frame._cellvalues[1][0]
    assert image.drawWidth <= 190.01
    assert image.drawHeight <= 128.01
