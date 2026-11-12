from datetime import date

from app.utils.dates import format_display_date, format_display_date_range
from app.utils.treatment_details import clinical_summary, family_label, resolved_sub_treatment, visit_items


def test_display_date_is_dd_mm_yy():
    assert format_display_date(date(2026, 9, 26)) == "26/09/26"
    assert format_display_date("2026-09-26") == "26/09/26"
    assert format_display_date_range(date(2026, 9, 1), date(2026, 9, 26)) == "01/09/26 to 26/09/26"


def test_resolved_sub_treatment_falls_back_to_details_and_name():
    assert resolved_sub_treatment(sub_treatment="Crown") == "Crown"
    assert resolved_sub_treatment(details={"sub_treatment": "RCT"}, treatment_name="RCT") == "RCT"
    assert resolved_sub_treatment(treatment_name="RCT") == "RCT"
    assert family_label("Crown") == "Prosthetic"
    assert family_label("RCT") == "RCT"


def test_visit_items_keep_each_treatment_separate():
    details = {
        "kind": "visit",
        "items": [
            {"kind": "rct", "sub_treatment": "RCT", "tooth_number": "16", "canals": 3},
            {"kind": "general", "sub_treatment": "Tooth Extraction", "tooth_number": "18"},
        ],
    }
    assert len(visit_items(details)) == 2
    summary = clinical_summary(details)
    assert "RCT" in summary
    assert "#16" in summary
    assert "Tooth Extraction" in summary
    assert "#18" in summary
    assert resolved_sub_treatment(details=details) == "RCT, Tooth Extraction"
