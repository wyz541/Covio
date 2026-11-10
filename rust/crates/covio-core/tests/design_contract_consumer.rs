use covio_core::contract_design;

#[test]
fn generated_contract_exposes_platform_fonts_and_typography() {
    assert_eq!(contract_design::SCHEMA_VERSION, "1.5.0");

    let windows = contract_design::platform_font("windows", "interface")
        .expect("Windows interface font mapping");
    assert_eq!(windows.family, "Segoe UI Variable");
    assert_eq!(windows.fallback_families, &["Segoe UI"]);
    assert_eq!(windows.file_names.first().copied(), Some("SegUIVar.ttf"));
    assert!(!windows.platforms.contains(&"macos"));

    let apple =
        contract_design::platform_font("macos", "interface").expect("Apple interface font mapping");
    assert_eq!(apple.family, "SF Pro");

    let body = contract_design::typography_token("typography/body").expect("body typography");
    assert_eq!(body.size, 13.0);
    assert_eq!(body.line_height, 18.0);
}

#[test]
fn generated_contract_exposes_semantics_focus_and_acceptance_ids() {
    let role = contract_design::semantic_role("role/focus/ring").expect("focus role");
    assert_eq!(role.category, "focus");
    assert!(role.token_keys.contains(&"token/color/focus-ring"));

    let focus = contract_design::focus_order("focus/file-area").expect("file-area focus order");
    assert_eq!(focus.steps.first().map(|step| step.order), Some(1));
    assert_eq!(focus.steps.last().map(|step| step.order), Some(5));

    assert!(
        contract_design::ACCEPTANCE_CRITERIA
            .iter()
            .any(|criterion| criterion.kind == "visual")
    );
    assert!(
        contract_design::ACCEPTANCE_CRITERIA
            .iter()
            .any(|criterion| criterion.kind == "behavior")
    );
}

#[test]
fn generated_contract_exposes_tokens_and_copy() {
    let canvas = contract_design::color_token("token/color/canvas").expect("canvas color");
    assert_eq!(canvas.light.red, 0xF2);
    assert_eq!(canvas.light.green, 0xF2);
    assert_eq!(canvas.light.blue, 0xF7);
    assert_eq!(canvas.light.alpha, 0xFF);

    let radius = contract_design::dimension_token("token/radius/panel").expect("panel radius");
    assert_eq!(radius.light, 22.0);

    let copy = contract_design::copy_entry("copy/app/name").expect("app name copy");
    assert_eq!(copy.en, "Covio");
}
