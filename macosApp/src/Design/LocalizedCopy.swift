import Foundation

/// 一条双语文案。语言顺序与 `docs/covio-design-contract.json` 的 `copy` 段一致。
///
/// `key` 是合同里的键路径。`ContractCopy` 生成的条目都带键；
/// 这个文件是唯一允许手写文案类型的地方，但文案本身一律从 `ContractCopy` 取。
struct LocalizedCopy: Sendable, Equatable {
    let key: String?
    let en: String
    let zhHans: String

    init(key: String? = nil, en: String, zhHans: String) {
        self.key = key
        self.en = en
        self.zhHans = zhHans
    }

    /// 按当前系统语言取文案。
    ///
    /// 合同只给 `en` 与 `zh-Hans` 两种。其它语言回落到英文。
    var text: String { text(for: CopyLocale.language) }

    /// 按指定语言取文案。设置里改了语言后，界面走这一条。
    func text(for language: AppLanguage) -> String {
        switch language {
        case .simplifiedChinese: zhHans
        case .english: en
        }
    }
}

/// 实际的界面语言。
///
/// 取值与 Rust core 的语言码一致：`en` 与 `zh-CN`。
enum AppLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-CN"

    /// 按配置里的语言码取语言。空码或认不出的码回落到系统语言。
    static func fromCode(_ code: String?) -> AppLanguage {
        AppLanguagePreference.fromCode(code).language
    }

    /// 格式化日期与数字用的区域。合同只给两种语言，所以区域也只有两种。
    var locale: Locale {
        switch self {
        case .simplifiedChinese: Locale(identifier: "zh-Hans")
        case .english: Locale(identifier: "en")
        }
    }
}

/// 语言偏好。
///
/// `AppConfig.language` 用空字符串表示跟随系统；手动选择时保存实际语言码。
enum AppLanguagePreference: String, CaseIterable, Sendable {
    case system = ""
    case english = "en"
    case simplifiedChinese = "zh-CN"

    init(language: AppLanguage) {
        self = AppLanguagePreference(rawValue: language.rawValue) ?? .system
    }

    /// 配置里的空值、`system` 和认不出的值都回到系统模式。
    static func fromCode(_ code: String?) -> AppLanguagePreference {
        guard let code else { return .system }
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty || normalized == "system" { return .system }
        if normalized.hasPrefix("zh") { return .simplifiedChinese }
        if normalized.hasPrefix("en") { return .english }
        return .system
    }

    /// 解析 Agent 可以传入的明确值。认不出的值返回 nil。
    static func parse(_ text: String) -> AppLanguagePreference? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty || normalized == "system" { return .system }
        let preference = fromCode(normalized)
        return preference == .system ? nil : preference
    }

    /// 解析后的实际界面语言。
    var language: AppLanguage {
        switch self {
        case .system: CopyLocale.language
        case .english: .english
        case .simplifiedChinese: .simplifiedChinese
        }
    }

    /// Agent 设置接口使用的可读值。
    var agentValue: String {
        self == .system ? "system" : rawValue
    }
}

enum CopyLocale {
    /// 把系统首选语言映射到首期支持的两种界面语言。
    static func language(preferredLanguages: [String]) -> AppLanguage {
        let preferred = preferredLanguages.first ?? "en"
        return preferred.lowercased().hasPrefix("zh") ? .simplifiedChinese : .english
    }

    /// 系统语言。
    static var language: AppLanguage {
        language(preferredLanguages: Locale.preferredLanguages)
    }
}
