//! Read-only design contract parser and application-side validation.

use covio_platform::FileStore;
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::path::Path;

/// Default contract path relative to the repository root.
pub const DEFAULT_CONTRACT_PATH: &str = "docs/covio-design-contract.json";

/// Design contract diagnostic severity.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum DesignContractSeverity {
    /// The contract is invalid.
    Error,
    /// The contract is valid, but the diagnostic should be reviewed.
    Warning,
}

impl DesignContractSeverity {
    /// Returns the stable display name.
    #[must_use]
    pub const fn name(self) -> &'static str {
        match self {
            Self::Error => "ERROR",
            Self::Warning => "WARNING",
        }
    }
}

/// One design contract diagnostic.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DesignContractDiagnostic {
    /// Diagnostic severity.
    pub severity: DesignContractSeverity,
    /// JSON path such as `tokens/token/motion/hub-expand`.
    pub path: String,
    /// Human-readable message.
    pub message: String,
}

impl DesignContractDiagnostic {
    /// Returns one display line.
    #[must_use]
    pub fn describe(&self) -> String {
        format!("{} {}: {}", self.severity.name(), self.path, self.message)
    }
}

/// Design contract validation result.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DesignContractValidationResult {
    /// Parsed contract. This is `None` when any error exists.
    pub contract: Option<DesignContract>,
    /// Errors and warnings.
    pub diagnostics: Vec<DesignContractDiagnostic>,
}

impl DesignContractValidationResult {
    /// Creates a valid result without diagnostics.
    #[must_use]
    pub fn ok(contract: DesignContract) -> Self {
        Self {
            contract: Some(contract),
            diagnostics: Vec::new(),
        }
    }

    /// Returns true when no error diagnostic exists.
    #[must_use]
    pub fn is_valid(&self) -> bool {
        !self
            .diagnostics
            .iter()
            .any(|diagnostic| diagnostic.severity == DesignContractSeverity::Error)
    }

    /// Returns all errors.
    #[must_use]
    pub fn errors(&self) -> Vec<&DesignContractDiagnostic> {
        self.diagnostics
            .iter()
            .filter(|diagnostic| diagnostic.severity == DesignContractSeverity::Error)
            .collect()
    }

    /// Returns all warnings.
    #[must_use]
    pub fn warnings(&self) -> Vec<&DesignContractDiagnostic> {
        self.diagnostics
            .iter()
            .filter(|diagnostic| diagnostic.severity == DesignContractSeverity::Warning)
            .collect()
    }
}

/// One localized design-contract copy entry.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DesignCopyEntry {
    /// Stable copy key.
    pub key: String,
    /// English copy.
    pub en: String,
    /// Simplified Chinese copy.
    #[serde(rename = "zhHans")]
    pub zh_hans: String,
}

/// One design token.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DesignToken {
    /// Stable token key.
    pub key: String,
    /// Token type.
    #[serde(rename = "type")]
    pub token_type: String,
    /// Intended use.
    pub purpose: String,
    /// Light value.
    pub light: Option<String>,
    /// Dark value.
    pub dark: Option<String>,
    /// Motion duration in milliseconds.
    pub duration_ms: Option<f64>,
    /// Minimum motion duration.
    pub min_ms: Option<f64>,
    /// Maximum motion duration.
    pub max_ms: Option<f64>,
    /// Reduced-motion duration.
    pub reduced_motion_ms: Option<f64>,
    /// Motion curve description.
    pub curve: Option<String>,
}

impl DesignToken {
    /// Returns true for a motion duration token.
    #[must_use]
    pub fn is_motion(&self) -> bool {
        self.token_type == "duration"
    }

    /// Returns whether a motion range exists and contains the selected duration.
    #[must_use]
    pub fn has_valid_motion_range(&self) -> bool {
        if !self.is_motion() {
            return true;
        }
        let (Some(low), Some(value), Some(high)) = (self.min_ms, self.duration_ms, self.max_ms)
        else {
            return false;
        };
        if value <= 0.0 || low <= 0.0 || high <= 0.0 || low > value || value > high {
            return false;
        }
        self.reduced_motion_ms
            .is_none_or(|reduced| reduced <= value)
    }
}

/// Read-only design contract model.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DesignContract {
    /// Contract schema version.
    pub schema_version: String,
    /// Design tokens.
    pub tokens: Vec<DesignToken>,
    /// Localized copy entries.
    pub copy: Vec<DesignCopyEntry>,
    /// Component keys in sorted order.
    pub components: Vec<String>,
    /// Platform mapping keys in sorted order.
    pub platform_mappings: Vec<String>,
}

impl DesignContract {
    /// Returns the motion tokens.
    pub fn motion_tokens(&self) -> impl Iterator<Item = &DesignToken> {
        self.tokens.iter().filter(|token| token.is_motion())
    }

    /// Finds a token by exact key.
    #[must_use]
    pub fn token(&self, key: &str) -> Option<&DesignToken> {
        self.tokens.iter().find(|token| token.key == key)
    }

    /// Finds a copy entry by exact key.
    #[must_use]
    pub fn entry(&self, key: &str) -> Option<&DesignCopyEntry> {
        self.copy.iter().find(|entry| entry.key == key)
    }
}

/// Design contract parser and validator.
pub struct DesignContractReader;

impl DesignContractReader {
    /// Returns the default contract path.
    #[must_use]
    pub const fn default_contract_path() -> &'static str {
        DEFAULT_CONTRACT_PATH
    }

    /// Parses and validates contract text. This method never panics on input.
    #[must_use]
    pub fn parse(text: &str) -> DesignContractValidationResult {
        let Ok(value) = serde_json::from_str::<Value>(text) else {
            return failure("", "合同不是合法的 JSON 对象");
        };
        let Value::Object(root) = value else {
            return failure("", "合同不是合法的 JSON 对象");
        };

        let mut diagnostics = Vec::new();
        let schema_version = object_string(&root, "schemaVersion");
        if schema_version.is_none() {
            diagnostics.push(diagnostic(
                DesignContractSeverity::Error,
                "schemaVersion",
                "缺 schemaVersion，或者它不是非空字符串",
            ));
        }

        let tokens = read_tokens(
            root.get("tokens").and_then(Value::as_object),
            &mut diagnostics,
        );
        let copy = read_copy(
            root.get("copy").and_then(Value::as_object),
            &mut diagnostics,
        );
        let components = read_components(
            root.get("components").and_then(Value::as_object),
            &mut diagnostics,
        );
        let platform_mappings = read_platform_mappings(
            root.get("platformMapping").and_then(Value::as_object),
            &mut diagnostics,
        );

        if tokens.is_empty() {
            diagnostics.push(missing("tokens"));
        }
        if copy.is_empty() {
            diagnostics.push(missing("copy"));
        }
        if components.is_empty() {
            diagnostics.push(missing("components"));
        }
        if platform_mappings.is_empty() {
            diagnostics.push(missing("platformMapping"));
        }

        let contract = if diagnostics
            .iter()
            .any(|diagnostic| diagnostic.severity == DesignContractSeverity::Error)
        {
            None
        } else {
            Some(DesignContract {
                schema_version: schema_version.expect("schema version checked"),
                tokens,
                copy,
                components,
                platform_mappings,
            })
        };
        DesignContractValidationResult {
            contract,
            diagnostics,
        }
    }

    /// Reads and parses a contract through the platform filesystem port.
    #[must_use]
    pub fn read(store: &dyn FileStore, path: &Path) -> DesignContractValidationResult {
        let bytes = match store.read(path) {
            Ok(Some(bytes)) => bytes,
            Ok(None) => {
                return failure(&path.to_string_lossy(), "读不到合同文件：文件不存在");
            }
            Err(error) => {
                return failure(
                    &path.to_string_lossy(),
                    &format!("读不到合同文件：{}", error.message()),
                );
            }
        };
        let Ok(text) = String::from_utf8(bytes) else {
            return failure(&path.to_string_lossy(), "读不到合同文件：不是 UTF-8");
        };
        Self::parse(&text)
    }
}

fn read_tokens(
    node: Option<&Map<String, Value>>,
    diagnostics: &mut Vec<DesignContractDiagnostic>,
) -> Vec<DesignToken> {
    let Some(node) = node else {
        return Vec::new();
    };
    let mut tokens = Vec::new();
    for (key, element) in node {
        let path = format!("tokens/{key}");
        let Some(entry) = element.as_object() else {
            diagnostics.push(diagnostic(DesignContractSeverity::Error, &path, "不是对象"));
            continue;
        };
        if !key.starts_with("token/") {
            diagnostics.push(diagnostic(
                DesignContractSeverity::Error,
                &path,
                "令牌键不以 token/ 开头",
            ));
        }
        let Some(token_type) = object_string(entry, "type") else {
            diagnostics.push(diagnostic(DesignContractSeverity::Error, &path, "缺 type"));
            continue;
        };
        let token = DesignToken {
            key: key.clone(),
            token_type: token_type.clone(),
            purpose: object_string(entry, "purpose").unwrap_or_default(),
            light: object_string(entry, "light"),
            dark: object_string(entry, "dark"),
            duration_ms: object_number(entry, "durationMs"),
            min_ms: object_number(entry, "minMs"),
            max_ms: object_number(entry, "maxMs"),
            reduced_motion_ms: object_number(entry, "reducedMotionMs"),
            curve: object_string(entry, "curve"),
        };
        match token_type.as_str() {
            "color" | "dimension" if token.light.is_none() || token.dark.is_none() => {
                diagnostics.push(diagnostic(
                    DesignContractSeverity::Error,
                    &path,
                    "颜色与尺寸令牌要有 light 与 dark",
                ));
            }
            "duration" if !token.has_valid_motion_range() => {
                diagnostics.push(diagnostic(
                    DesignContractSeverity::Error,
                    &path,
                    &format!(
                        "动效时长的范围不成立：minMs={:?} durationMs={:?} maxMs={:?} reducedMotionMs={:?}",
                        token.min_ms, token.duration_ms, token.max_ms, token.reduced_motion_ms
                    ),
                ));
            }
            "color" | "dimension" | "duration" => {}
            _ => diagnostics.push(diagnostic(
                DesignContractSeverity::Error,
                &path,
                &format!("认不出的令牌类型：{token_type}"),
            )),
        }
        if token.purpose.trim().is_empty() {
            diagnostics.push(diagnostic(
                DesignContractSeverity::Warning,
                &path,
                "缺 purpose",
            ));
        }
        tokens.push(token);
    }
    tokens
}

fn read_copy(
    node: Option<&Map<String, Value>>,
    diagnostics: &mut Vec<DesignContractDiagnostic>,
) -> Vec<DesignCopyEntry> {
    let Some(node) = node else {
        return Vec::new();
    };
    let mut copy = Vec::new();
    for (key, element) in node {
        let path = format!("copy/{key}");
        let Some(entry) = element.as_object() else {
            diagnostics.push(diagnostic(DesignContractSeverity::Error, &path, "不是对象"));
            continue;
        };
        if !key.starts_with("copy/") {
            diagnostics.push(diagnostic(
                DesignContractSeverity::Error,
                &path,
                "文案键不以 copy/ 开头",
            ));
        }
        let en = object_string(entry, "en");
        let zh_hans = object_string(entry, "zh-Hans");
        let (Some(en), Some(zh_hans)) = (en, zh_hans) else {
            diagnostics.push(diagnostic(
                DesignContractSeverity::Error,
                &path,
                "文案要同时有 en 与 zh-Hans，且都不能为空",
            ));
            continue;
        };
        copy.push(DesignCopyEntry {
            key: key.clone(),
            en,
            zh_hans,
        });
    }
    copy
}

fn read_components(
    node: Option<&Map<String, Value>>,
    diagnostics: &mut Vec<DesignContractDiagnostic>,
) -> Vec<String> {
    let Some(node) = node else {
        return Vec::new();
    };
    for (key, element) in node {
        let path = format!("components/{key}");
        let Some(entry) = element.as_object() else {
            diagnostics.push(diagnostic(DesignContractSeverity::Error, &path, "不是对象"));
            continue;
        };
        let Some(mapping) = entry.get("swiftMapping").and_then(Value::as_object) else {
            diagnostics.push(diagnostic(
                DesignContractSeverity::Error,
                &path,
                "缺 swiftMapping。macOS 下每个组件都要有 Swift 落点",
            ));
            continue;
        };
        if object_string(mapping, "target").is_none() {
            diagnostics.push(diagnostic(
                DesignContractSeverity::Error,
                &format!("{path}/swiftMapping"),
                "缺 target",
            ));
        }
    }
    let mut keys: Vec<_> = node.keys().cloned().collect();
    keys.sort();
    keys
}

fn read_platform_mappings(
    node: Option<&Map<String, Value>>,
    diagnostics: &mut Vec<DesignContractDiagnostic>,
) -> Vec<String> {
    let Some(node) = node else {
        return Vec::new();
    };
    for (key, element) in node {
        let path = format!("platformMapping/{key}");
        let Some(entry) = element.as_object() else {
            diagnostics.push(diagnostic(DesignContractSeverity::Error, &path, "不是对象"));
            continue;
        };
        if object_string(entry, "status").is_none() {
            diagnostics.push(diagnostic(
                DesignContractSeverity::Error,
                &path,
                "缺 status",
            ));
        }
        if object_string(entry, "swiftRuntimeTarget").is_none() {
            diagnostics.push(diagnostic(
                DesignContractSeverity::Error,
                &path,
                "缺 swiftRuntimeTarget",
            ));
        }
    }
    let mut keys: Vec<_> = node.keys().cloned().collect();
    keys.sort();
    keys
}

fn object_string(object: &Map<String, Value>, key: &str) -> Option<String> {
    let value = object.get(key)?;
    let text = match value {
        Value::String(value) => value.clone(),
        Value::Number(value) => value.to_string(),
        Value::Bool(value) => value.to_string(),
        Value::Null | Value::Array(_) | Value::Object(_) => return None,
    };
    (!text.trim().is_empty()).then_some(text)
}

fn object_number(object: &Map<String, Value>, key: &str) -> Option<f64> {
    let value = object.get(key)?;
    match value {
        Value::Number(number) => number.as_f64(),
        Value::String(value) => value.parse().ok(),
        _ => None,
    }
}

fn diagnostic(
    severity: DesignContractSeverity,
    path: &str,
    message: &str,
) -> DesignContractDiagnostic {
    DesignContractDiagnostic {
        severity,
        path: path.to_owned(),
        message: message.to_owned(),
    }
}

fn missing(section: &str) -> DesignContractDiagnostic {
    diagnostic(
        DesignContractSeverity::Error,
        section,
        &format!("缺 {section} 段，或者它是空的"),
    )
}

fn failure(path: &str, message: &str) -> DesignContractValidationResult {
    DesignContractValidationResult {
        contract: None,
        diagnostics: vec![diagnostic(DesignContractSeverity::Error, path, message)],
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use covio_platform::{FileStore, PlatformError};
    use std::path::{Path, PathBuf};

    fn minimal(
        schema_version: &str,
        tokens: &str,
        copy: &str,
        components: &str,
        platform_mapping: &str,
    ) -> String {
        format!(
            r###"{{
  "schemaVersion": "{schema_version}",
  "tokens": {tokens},
  "copy": {copy},
  "components": {components},
  "platformMapping": {platform_mapping}
}}"###
        )
    }

    fn valid_minimal() -> String {
        minimal(
            "1.3.0",
            r###"{"token/color/ink":{"type":"color","light":"#000","dark":"#fff","purpose":"x"}}"###,
            r###"{"copy/app/name":{"en":"Covio","zh-Hans":"Covio"}}"###,
            r###"{"component/x":{"name":"X","swiftMapping":{"target":"MacX","behavior":"b"}}}"###,
            r###"{"platform/system/menus":{"status":"native-source-mapped","swiftRuntimeTarget":"StatusItemController"}}"###,
        )
    }

    #[test]
    fn shipped_contract_parses_and_validates() {
        let result = DesignContractReader::parse(include_str!(
            "../../../../docs/covio-design-contract.json"
        ));
        assert!(
            result.is_valid(),
            "{:?}",
            result
                .errors()
                .iter()
                .map(|error| error.describe())
                .collect::<Vec<_>>()
        );
        let contract = result.contract.expect("contract");
        assert_eq!(contract.schema_version, "1.5.0");
        assert_eq!(contract.tokens.len(), 163);
        assert_eq!(contract.copy.len(), 979);
        assert_eq!(contract.components.len(), 30);
        assert_eq!(contract.platform_mappings.len(), 33);
        assert_eq!(contract.motion_tokens().count(), 11);
    }

    #[test]
    fn shipped_contract_keeps_motion_and_hub_copy() {
        let contract = DesignContractReader::parse(include_str!(
            "../../../../docs/covio-design-contract.json"
        ))
        .contract
        .expect("contract");
        let motion = contract.token("token/motion/hub-expand").expect("motion");
        assert!(motion.is_motion());
        assert!(motion.has_valid_motion_range());
        assert_eq!(motion.curve.as_deref(), Some("弹性曲线"));
        assert!(contract.entry("copy/notch-hub/state/ready").is_some());
    }

    #[test]
    fn generated_rust_motion_tokens_match_contract() {
        let contract = DesignContractReader::parse(include_str!(
            "../../../../docs/covio-design-contract.json"
        ))
        .contract
        .expect("contract");
        assert_eq!(
            crate::contract_motion::MOTION_DURATIONS.len(),
            contract.motion_tokens().count()
        );
        for token in contract.motion_tokens() {
            let (_, duration) = crate::contract_motion::MOTION_DURATIONS
                .iter()
                .find(|(key, _)| *key == token.key)
                .expect("generated motion token");
            let milliseconds = token.duration_ms.expect("motion duration");
            assert_eq!(
                duration.as_micros(),
                (milliseconds * 1000.0).round() as u128,
                "motion token drift: {}",
                token.key
            );
        }
    }

    #[test]
    fn lookup_returns_the_known_entry() {
        let contract = DesignContractReader::parse(&valid_minimal())
            .contract
            .expect("contract");
        assert_eq!(
            contract
                .token("token/color/ink")
                .map(|token| token.key.as_str()),
            Some("token/color/ink")
        );
        assert_eq!(
            contract
                .entry("copy/app/name")
                .map(|entry| entry.en.as_str()),
            Some("Covio")
        );
        assert_eq!(contract.token("missing"), None);
        assert_eq!(contract.entry("missing"), None);
    }

    #[test]
    fn broken_and_non_object_json_become_diagnostics() {
        for text in ["{", "[]", "null", "42"] {
            let result = DesignContractReader::parse(text);
            assert!(!result.is_valid());
            assert_eq!(result.errors()[0].path, "");
            assert_eq!(result.errors()[0].message, "合同不是合法的 JSON 对象");
        }
    }

    #[test]
    fn missing_sections_are_reported_one_by_one() {
        let result = DesignContractReader::parse("{}");
        assert!(!result.is_valid());
        let paths: Vec<_> = result
            .errors()
            .iter()
            .map(|error| error.path.as_str())
            .collect();
        for path in [
            "schemaVersion",
            "tokens",
            "copy",
            "components",
            "platformMapping",
        ] {
            assert!(paths.contains(&path), "{path}");
        }
    }

    #[test]
    fn blank_schema_version_is_rejected() {
        let result = DesignContractReader::parse(&valid_minimal().replace("1.3.0", " "));
        assert!(!result.is_valid());
        assert!(
            result
                .errors()
                .iter()
                .any(|error| error.path == "schemaVersion")
        );
    }

    #[test]
    fn color_tokens_need_both_values() {
        let result = DesignContractReader::parse(&minimal(
            "1.3.0",
            r###"{"token/color/ink":{"type":"color","purpose":"x"}}"###,
            r###"{"copy/app/name":{"en":"Covio","zh-Hans":"Covio"}}"###,
            r###"{"component/x":{"swiftMapping":{"target":"MacX"}}}"###,
            r###"{"platform/system/menus":{"status":"mapped","swiftRuntimeTarget":"StatusItemController"}}"###,
        ));
        assert!(!result.is_valid());
        assert!(
            result
                .errors()
                .iter()
                .any(|error| error.path == "tokens/token/color/ink")
        );
    }

    #[test]
    fn unknown_token_type_is_rejected() {
        let result = DesignContractReader::parse(&minimal(
            "1.3.0",
            r###"{"token/x/y":{"type":"gradient","purpose":"x"}}"###,
            r###"{"copy/app/name":{"en":"Covio","zh-Hans":"Covio"}}"###,
            r###"{"component/x":{"swiftMapping":{"target":"MacX"}}}"###,
            r###"{"platform/system/menus":{"status":"mapped","swiftRuntimeTarget":"StatusItemController"}}"###,
        ));
        assert!(!result.is_valid());
        assert!(
            result
                .errors()
                .iter()
                .any(|error| error.message.contains("认不出的令牌类型"))
        );
    }

    #[test]
    fn motion_ranges_are_validated() {
        for token in [
            r###"{"token/motion/x":{"type":"duration","purpose":"x","durationMs":100,"minMs":200,"maxMs":300}}"###,
            r###"{"token/motion/x":{"type":"duration","purpose":"x","durationMs":120,"minMs":120,"maxMs":120,"reducedMotionMs":500}}"###,
        ] {
            let result = DesignContractReader::parse(&minimal(
                "1.3.0",
                token,
                r###"{"copy/app/name":{"en":"Covio","zh-Hans":"Covio"}}"###,
                r###"{"component/x":{"swiftMapping":{"target":"MacX"}}}"###,
                r###"{"platform/system/menus":{"status":"mapped","swiftRuntimeTarget":"StatusItemController"}}"###,
            ));
            assert!(!result.is_valid());
            assert!(
                result
                    .errors()
                    .iter()
                    .any(|error| error.path == "tokens/token/motion/x")
            );
        }
        let result = DesignContractReader::parse(&minimal(
            "1.3.0",
            r###"{"token/motion/x":{"type":"duration","purpose":"x","curve":"缓出","durationMs":250,"minMs":220,"maxMs":280,"reducedMotionMs":120}}"###,
            r###"{"copy/app/name":{"en":"Covio","zh-Hans":"Covio"}}"###,
            r###"{"component/x":{"swiftMapping":{"target":"MacX"}}}"###,
            r###"{"platform/system/menus":{"status":"mapped","swiftRuntimeTarget":"StatusItemController"}}"###,
        ));
        assert!(result.is_valid(), "{:?}", result.errors());
        let token = result
            .contract
            .unwrap()
            .token("token/motion/x")
            .cloned()
            .unwrap();
        assert_eq!(token.min_ms, Some(220.0));
        assert_eq!(token.duration_ms, Some(250.0));
        assert_eq!(token.max_ms, Some(280.0));
        assert_eq!(token.reduced_motion_ms, Some(120.0));
        assert_eq!(token.curve.as_deref(), Some("缓出"));
    }

    #[test]
    fn copy_needs_both_languages_and_component_needs_swift_mapping() {
        let result = DesignContractReader::parse(&minimal(
            "1.3.0",
            r###"{"token/color/ink":{"type":"color","light":"#000","dark":"#fff","purpose":"x"}}"###,
            r###"{"copy/a":{"en":"Hello"}}"###,
            r###"{"component/x":{"name":"X"}}"###,
            r###"{"platform/system/menus":{"status":"mapped","swiftRuntimeTarget":"StatusItemController"}}"###,
        ));
        assert!(!result.is_valid());
        assert!(
            result
                .errors()
                .iter()
                .any(|error| error.path == "copy/copy/a")
        );
        assert!(
            result
                .errors()
                .iter()
                .any(|error| error.path == "components/component/x")
        );
    }

    #[test]
    fn platform_mapping_needs_a_swift_target() {
        let result = DesignContractReader::parse(&minimal(
            "1.3.0",
            r###"{"token/color/ink":{"type":"color","light":"#000","dark":"#fff","purpose":"x"}}"###,
            r###"{"copy/app/name":{"en":"Covio","zh-Hans":"Covio"}}"###,
            r###"{"component/x":{"swiftMapping":{"target":"MacX"}}}"###,
            r###"{"platform/system/menus":{"status":"native-source-mapped"}}"###,
        ));
        assert!(!result.is_valid());
        assert!(
            result
                .errors()
                .iter()
                .any(|error| error.message.contains("swiftRuntimeTarget"))
        );
    }

    #[test]
    fn missing_purpose_is_only_a_warning() {
        let result = DesignContractReader::parse(&minimal(
            "1.3.0",
            r###"{"token/color/ink":{"type":"color","light":"#000","dark":"#fff"}}"###,
            r###"{"copy/app/name":{"en":"Covio","zh-Hans":"Covio"}}"###,
            r###"{"component/x":{"swiftMapping":{"target":"MacX"}}}"###,
            r###"{"platform/system/menus":{"status":"mapped","swiftRuntimeTarget":"StatusItemController"}}"###,
        ));
        assert!(result.is_valid(), "{:?}", result.errors());
        assert_eq!(result.warnings().len(), 1);
        assert_eq!(result.warnings()[0].path, "tokens/token/color/ink");
        assert!(result.contract.is_some());
    }

    #[test]
    fn key_prefixes_are_checked() {
        let result = DesignContractReader::parse(&minimal(
            "1.3.0",
            r###"{"color/ink":{"type":"color","light":"#000","dark":"#fff","purpose":"x"}}"###,
            r###"{"app/name":{"en":"Covio","zh-Hans":"Covio"}}"###,
            r###"{"component/x":{"swiftMapping":{"target":"MacX"}}}"###,
            r###"{"platform/system/menus":{"status":"mapped","swiftRuntimeTarget":"StatusItemController"}}"###,
        ));
        assert!(!result.is_valid());
        assert!(
            result
                .errors()
                .iter()
                .any(|error| error.message.contains("令牌键不以 token/"))
        );
        assert!(
            result
                .errors()
                .iter()
                .any(|error| error.message.contains("文案键不以 copy/"))
        );
    }

    #[test]
    fn old_contracts_and_unknown_fields_are_accepted() {
        let result = DesignContractReader::parse(&minimal(
            "1.0.0",
            r###"{"token/color/ink":{"type":"color","light":"#000","dark":"#fff","purpose":"x","future":true}}"###,
            r###"{"copy/app/name":{"en":"Covio","zh-Hans":"Covio","future":"x"}}"###,
            r###"{"component/x":{"swiftMapping":{"target":"MacX"},"future":1}}"###,
            r###"{"platform/system/menus":{"status":"mapped","swiftRuntimeTarget":"StatusItemController","future":[]}}"###,
        ));
        assert!(result.is_valid(), "{:?}", result.errors());
        assert_eq!(result.contract.unwrap().schema_version, "1.0.0");
    }

    struct MemoryFiles(Option<Vec<u8>>);

    impl FileStore for MemoryFiles {
        fn read(&self, _path: &Path) -> Result<Option<Vec<u8>>, PlatformError> {
            Ok(self.0.clone())
        }
        fn create_dir_all(&self, _path: &Path) -> Result<(), PlatformError> {
            Ok(())
        }
        fn write_atomic(&self, _path: &Path, _contents: &[u8]) -> Result<(), PlatformError> {
            Ok(())
        }
        fn remove_file(&self, _path: &Path) -> Result<bool, PlatformError> {
            Ok(false)
        }
        fn remove_tree(&self, _path: &Path) -> Result<(), PlatformError> {
            Ok(())
        }
    }

    #[test]
    fn missing_file_becomes_a_diagnostic() {
        let result = DesignContractReader::read(
            &MemoryFiles(None),
            &PathBuf::from("covio-missing-contract.json"),
        );
        assert!(!result.is_valid());
        assert!(result.contract.is_none());
        assert!(result.errors()[0].message.starts_with("读不到合同文件"));
    }

    #[test]
    fn default_path_points_at_the_repository_contract() {
        assert_eq!(
            DesignContractReader::default_contract_path(),
            "docs/covio-design-contract.json"
        );
    }
}
