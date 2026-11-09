use covio_core::workbench_interaction::{
    DisplaySelection, EasingSpec, Platform, PlatformOverrideSpec, TransitionDirection,
    TriggerAlignment, TriggerShape, WORKBENCH_INTERACTION, WorkbenchInteractionSpec,
};
use serde_json::Value;
use std::time::Duration;

fn committed_contract() -> Value {
    serde_json::from_str(include_str!(
        "../../../../docs/macos-interaction-contract.json"
    ))
    .expect("committed Workbench interaction contract")
}

#[test]
fn typed_spec_preserves_the_macos_contract() {
    let contract = committed_contract();
    assert_eq!(
        WORKBENCH_INTERACTION.contract_id,
        contract["contractId"].as_str().expect("contract id")
    );
    assert_eq!(
        WORKBENCH_INTERACTION.schema_version,
        contract["schemaVersion"].as_str().expect("schema version")
    );
    assert_eq!(
        WORKBENCH_INTERACTION.trigger.geometry.alignment,
        TriggerAlignment::TopCenter
    );
    assert_eq!(
        WORKBENCH_INTERACTION.trigger.geometry.display_selection,
        DisplaySelection::PointerDisplayThenMainFallback
    );
    assert_eq!(
        WORKBENCH_INTERACTION.trigger.geometry.notched_display,
        TriggerShape::Notch
    );
    assert_eq!(
        WORKBENCH_INTERACTION.trigger.geometry.notchless_display,
        TriggerShape::CenteredBand
    );
    assert_eq!(
        WORKBENCH_INTERACTION.reveal.direction,
        TransitionDirection::TopToBottom
    );
    assert_eq!(
        WORKBENCH_INTERACTION.conceal.direction,
        TransitionDirection::BottomToTop
    );
    assert!(matches!(
        WORKBENCH_INTERACTION.reveal.easing,
        EasingSpec::Spring { .. }
    ));
    assert_eq!(WORKBENCH_INTERACTION.conceal.easing, EasingSpec::EaseOut);
}

#[test]
fn duration_methods_use_the_committed_contract() {
    let contract = committed_contract();
    assert_eq!(
        WORKBENCH_INTERACTION.reveal_duration(Platform::Windows),
        Duration::from_millis(
            contract["reveal"]["durationMs"]
                .as_u64()
                .expect("reveal duration")
        )
    );
    assert_eq!(
        WORKBENCH_INTERACTION.conceal_duration(Platform::Windows),
        Duration::from_millis(
            contract["conceal"]["durationMs"]
                .as_u64()
                .expect("conceal duration")
        )
    );
    assert_eq!(
        WORKBENCH_INTERACTION.reduced_motion_duration(Platform::Windows),
        Duration::from_millis(
            contract["reducedMotion"]["durationMs"]
                .as_u64()
                .expect("reduced motion duration")
        )
    );
    assert_eq!(
        WORKBENCH_INTERACTION.pointer_exit_collapse_duration(Platform::Windows),
        Duration::from_millis(
            contract["trigger"]["pointerExitCollapseMs"]
                .as_u64()
                .expect("pointer exit duration")
        )
    );
}

#[test]
fn platform_overrides_change_effective_durations() {
    let overrides: &'static [PlatformOverrideSpec] = Box::leak(Box::new([PlatformOverrideSpec {
        id: "windows-test-reveal",
        platform: Platform::Windows,
        field: "reveal.durationMs",
        value: 300.0,
        reason: "test",
        evidence: &["test evidence"],
    }]));
    let spec = WorkbenchInteractionSpec {
        platform_overrides: overrides,
        ..WORKBENCH_INTERACTION
    };

    assert_eq!(
        spec.platform_value(Platform::Windows, "reveal.durationMs"),
        Some(300.0)
    );
    assert_eq!(
        spec.reveal_duration(Platform::Windows),
        Duration::from_millis(300)
    );
}

#[test]
fn generated_overrides_match_the_committed_contract() {
    let contract = committed_contract();
    let expected = contract["platformOverrides"]
        .as_array()
        .expect("platform overrides");
    assert_eq!(
        WORKBENCH_INTERACTION.platform_overrides.len(),
        expected.len()
    );

    for (generated, source) in WORKBENCH_INTERACTION
        .platform_overrides
        .iter()
        .zip(expected)
    {
        assert_eq!(generated.id, source["id"].as_str().expect("override id"));
        assert_eq!(
            generated.field,
            source["field"].as_str().expect("override field")
        );
        assert_eq!(
            generated.value,
            source["value"].as_f64().expect("override value")
        );
        assert_eq!(
            generated.reason,
            source["reason"].as_str().expect("override reason")
        );
    }
}
