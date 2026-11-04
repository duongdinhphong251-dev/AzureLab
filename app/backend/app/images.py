import io
import warnings
from PIL import Image, ImageOps, UnidentifiedImageError
from fastapi import HTTPException

Image.MAX_IMAGE_PIXELS = 20_000_000


def normalize_image(data, limit):
    if not data or len(data) > limit:
        raise HTTPException(413, "Ảnh phải có dung lượng từ 1 byte đến 5 MB.")
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(data)) as source:
                if source.format not in {"JPEG", "PNG", "WEBP"}:
                    raise HTTPException(415, "Chỉ hỗ trợ ảnh JPG, PNG hoặc WebP.")
                source.load()
                result = ImageOps.exif_transpose(source)
                result.thumbnail((2400, 2400))
                # Re-encode content: never serve an uploaded SVG/HTML or trust file extension.
                target = io.BytesIO()
                if "A" in result.getbands() or "transparency" in result.info:
                    result.convert("RGBA").save(target, "PNG")
                    content_type, extension = "image/png", "png"
                else:
                    result.convert("RGB").save(target, "JPEG", quality=88)
                    content_type, extension = "image/jpeg", "jpg"
                cleaned = target.getvalue()
                if len(cleaned) > limit:
                    raise HTTPException(413, "Ảnh sau xử lý vượt quá 5 MB.")
                return cleaned, content_type, extension
    except (UnidentifiedImageError, OSError, ValueError,
            Image.DecompressionBombError, Image.DecompressionBombWarning):
        raise HTTPException(415, "File không phải ảnh hợp lệ hoặc kích thước ảnh quá lớn.")
