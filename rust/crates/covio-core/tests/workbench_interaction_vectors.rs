use covio_core::workbench_interaction::{
    EasingSpec, Platform, TransitionDirection, WORKBENCH_INTERACTION,
};
use covio_core::workbench_interaction_runtime::{
    DisplayRect, transition_progress, trigger_contains,
};
use serde_json::Value;
use std::collections::BTreeSet;
use std::path::Path;

fn vectors() -> Value {
    serde_json::from_str(include_str!(
        "../../../../docs/macos-interaction-contract.vectors.json"
    ))
    .expect("Workbench interaction vectors")
}

fn transition(key: &str) -> (EasingSpec, f64) {
    match key {
        "reveal" => (
            WORKBENCH_INTERACTION.reveal.easing,
            WORKBENCH_INTERACTION.reveal.duration_ms / 1000.0,
        ),
        "conceal" => (
            WORKBENCH_INTERACTION.conceal.easing,
            WORKBENCH_INTERACTION.conceal.duration_ms / 1000.0,
        ),
        _ => panic!("unknown transition: {key}"),
    }
}

#[test]
fn trigger_points_match_the_shared_vectors() {
    let vectors = vectors();
    let trigger = &vectors["trigger"];
    let display = DisplayRect {
        left: trigger["display"]["left"].as_f64().expect("display left"),
        top: trigger["display"]["top"].as_f64().expect("display top"),
        width: trigger["display"]["width"].as_f64().expect("display width"),
        height: trigger["display"]["height"]
            .as_f64()
            .expect("display height"),
    };
    for point in trigger["points"].as_array().expect("trigger points") {
        let x = point["x"].as_f64().expect("x");
        let y = point["y"].as_f64().expect("y");
        let inside = point["inside"].as_bool().expect("inside");
        assert_eq!(
            trigger_contains(Platform::Windows, display, x, y),
            inside,
            "trigger point ({x}, {y})"
        );
    }
}

#[test]
fn easing_samples_match_with_the_explicit_tolerance() {
    let vectors = vectors();
    let tolerance = vectors["easing"]["tolerance"]
        .as_f64()
        .expect("easing tolerance");
    for transition_vector in vectors["easing"]["transitions"]
        .as_array()
        .expect("easing transitions")
    {
        let key = transition_vector["contractKey"]
            .as_str()
            .expect("transition key");
        let (easing, duration_seconds) = transition(key);
        for sample in transition_vector["samples"].as_array().expect("samples") {
            let time = sample["time"].as_f64().expect("sample time");
            let expected = sample["progress"].as_f64().expect("sample progress");
            let actual = transition_progress(easing, duration_seconds, time);
            assert!(
                (actual - expected).abs() <= tolerance,
                "{key} at {time}: expected {expected}, got {actual}, tolerance {tolerance}"
            );
        }
    }
}

#[test]
fn state_transitions_match_the_contract_directions() {
    let vectors = vectors();
    let transitions = vectors["stateTransitions"]
        .as_array()
        .expect("state transitions");
    assert_eq!(transitions.len(), 2);
    assert_eq!(transitions[0]["direction"].as_str(), Some("topToBottom"));
    assert_eq!(
        WORKBENCH_INTERACTION.reveal.direction,
        TransitionDirection::TopToBottom
    );
    assert_eq!(transitions[1]["direction"].as_str(), Some("bottomToTop"));
    assert_eq!(
        WORKBENCH_INTERACTION.conceal.direction,
        TransitionDirection::BottomToTop
    );
}

#[test]
fn platform_mappings_and_contract_coverage_are_complete() {
    let vectors = vectors();
    let mappings = vectors["platformMappings"]
        .as_array()
        .expect("platform mappings");
    let expected_fields: BTreeSet<_> = mappings
        .iter()
        .map(|entry| entry["field"].as_str().expect("mapping field").to_owned())
        .collect();
    let actual_fields: BTreeSet<_> = WORKBENCH_INTERACTION
        .platform_overrides
        .iter()
        .map(|entry| entry.field.to_owned())
        .collect();
    assert_eq!(actual_fields, expected_fields);
    for mapping in mappings {
        let field = mapping["field"].as_str().expect("mapping field");
        let expected_value = mapping["value"].as_f64().expect("mapping value");
        let actual_value = WORKBENCH_INTERACTION
            .platform_overrides
            .iter()
            .find(|entry| entry.field == field)
            .map(|entry| entry.value)
            .expect("generated platform override");
        assert_eq!(actual_value, expected_value, "{field}");
    }

    let tested_values = vectors["testedContractKeys"]
        .as_array()
        .expect("tested keys");
    assert_eq!(tested_values.len(), 24);
    let tested: BTreeSet<_> = tested_values
        .iter()
        .map(|value| value.as_str().expect("tested key"))
        .collect();
    assert_eq!(tested.len(), tested_values.len());
    for key in [
        "trigger.dwellMs",
        "trigger.cooldownMs",
        "trigger.geometry.centeredHalfWidthPercent",
        "trigger.geometry.topEdgeThicknessPixels",
        "reveal.direction",
        "reveal.easing",
        "conceal.direction",
        "conceal.easing",
        "reducedMotion.effect",
        "geometry.panelWidthPoints",
        "geometry.panelCornerRadiusPoints",
    ] {
        assert!(tested.contains(key), "missing tested contract key: {key}");
    }
}

#[test]
fn vector_metadata_and_evidence_are_complete() {
    let vectors = vectors();
    assert_eq!(
        vectors["contractId"].as_str(),
        Some(WORKBENCH_INTERACTION.contract_id)
    );
    assert_eq!(
        vectors["contractSchemaVersion"].as_str(),
        Some(WORKBENCH_INTERACTION.schema_version)
    );
    assert_eq!(vectors["platform"].as_str(), Some("windows"));
    assert_eq!(vectors["reducedMotion"]["effect"].as_str(), Some("opacity"));
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../..");
    for evidence in vectors["evidence"].as_array().expect("evidence") {
        assert!(
            evidence["contractKey"].as_str().is_some(),
            "evidence must name a contract key"
        );
        for path in evidence["paths"].as_array().expect("evidence paths") {
            let path = path.as_str().expect("evidence path");
            assert!(root.join(path).exists(), "missing evidence path: {path}");
        }
    }
}
