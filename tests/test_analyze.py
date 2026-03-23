import pytest
from unittest.mock import patch

FAKE_PAGES = [{"page": 1, "text": "Once upon a time"}, {"page": 2, "text": "The end"}]

def _fake_image():
    """Minimal valid JPEG bytes."""
    return b"\xff\xd8\xff\xe0" + b"\x00" * 100

@patch("backend.routers.analyze.analyze_pages", return_value=FAKE_PAGES)
def test_analyze_returns_pages(mock_svc, client):
    response = client.post(
        "/analyze",
        data={"vlm_provider": "gemini"},
        files=[("images", ("page1.jpg", _fake_image(), "image/jpeg"))],
    )
    assert response.status_code == 200
    assert response.json() == {"pages": FAKE_PAGES}

@patch("backend.routers.analyze.analyze_pages", return_value=FAKE_PAGES)
def test_analyze_passes_bytes_to_service(mock_svc, client):
    img = _fake_image()
    client.post(
        "/analyze",
        data={"vlm_provider": "gpt4o"},
        files=[("images", ("p1.jpg", img, "image/jpeg"))],
    )
    mock_svc.assert_called_once_with(
        image_bytes_list=[img],
        vlm_provider="gpt4o",
    )

@patch("backend.routers.analyze.analyze_pages", side_effect=ValueError("VLM returned invalid JSON"))
def test_analyze_returns_422_on_vlm_error(mock_svc, client):
    response = client.post(
        "/analyze",
        data={"vlm_provider": "gemini"},
        files=[("images", ("p1.jpg", _fake_image(), "image/jpeg"))],
    )
    assert response.status_code == 422

def test_analyze_requires_images(client):
    response = client.post("/analyze", data={"vlm_provider": "gemini"})
    assert response.status_code == 422

def test_analyze_requires_vlm_provider(client):
    response = client.post(
        "/analyze",
        files=[("images", ("p1.jpg", b"\xff\xd8", "image/jpeg"))],
    )
    assert response.status_code == 422
