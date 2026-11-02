package com.wyz.covio.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonObject

/** 工作台配置的版本。字段的含义变了就加一。 */
const val WORKBENCH_SCHEMA_VERSION = 3

/** 组件没有显式网格位置。旧配置与新组件都从这一值开始。 */
const val WIDGET_AUTOMATIC_POSITION = -1

/** id 与种类名的长度上限。挡住坏文件里的超长字符串。 */
private const val MAX_ID_LENGTH = 64
private const val MAX_KIND_LENGTH = 64

/** 工作区名字的长度上限。tab bar 一行放不下更长的名字。 */
private const val MAX_TITLE_LENGTH = 24

/**
 * 工作区的种类。
 *
 * 术语按需求文档第 2 节：工作区是 Pane，组件是 Widget。
 *
 * **显示名不进配置文件。** 内置工作区的名字来自设计合同
 * （`copy/hub/tab/<键>`）。名字存进文件后，换语言时不会跟着变。
 * 所以模型只存种类，宿主按键去读文案。
 *
 * [BOARD] 是用户自建的工作区。自建工作区没有模块页面，只显示组件网格。
 */
@Serializable
enum class PaneKind {
    @SerialName("now") NOW,
    @SerialName("agent") AGENT,
    @SerialName("clipboard") CLIPBOARD,
    @SerialName("files") FILES,
    /** v1 的内置截图工作区。schema 2 读取后删除，仅保留反序列化能力。 */
    @SerialName("screenshots") SCREENSHOTS,
    @SerialName("devices") DEVICES,
    @SerialName("settings") SETTINGS,
    @SerialName("board") BOARD,
    ;

    /** 序列化用的键。也是内置工作区的固定 id。测试盯着它与 `@SerialName` 一致。 */
    val key: String get() = name.lowercase()

    /** 是不是内置或历史内置工作区。历史截图工作区也归入这一组，防止用户重新添加。 */
    val isBuiltin: Boolean get() = this != BOARD

    /**
     * 是否出现在工作台顶栏。
     *
     * 助手与设置仍保留在旧配置里，避免升级时丢用户数据。
     * 两者的入口已经移出工作台导航，所以不能画成可切换工作区。
     */
    val appearsInWorkbenchNavigation: Boolean get() = when (this) {
        AGENT, SETTINGS -> false
        NOW, CLIPBOARD, FILES, SCREENSHOTS, DEVICES, BOARD -> true
    }

    /** 是否属于 schema 2 的默认内置工作区。截图工作区只用于读取旧配置。 */
    val isCurrentBuiltin: Boolean get() = isBuiltin && this != SCREENSHOTS

    /**
     * 内置工作区的固定 id。
     *
     * id 固定，宿主随时找得到「设置」这个工作区。用户改名不改 id。
     * 自建工作区的 id 由宿主生成。
     */
    val defaultId: String get() = key

    /**
     * 显示名的文案键。自建工作区没有内置名字，返回 null。
     * 宿主用这个键读生成的 `ContractCopy`，不自己写文案。
     */
    val titleCopyKey: String? get() = if (isBuiltin) "copy/hub/tab/$key" else null
}

/**
 * 组件卡片的尺寸档位。
 *
 * 存档位不存像素。面板宽度随屏幕变，存像素在窄屏上会溢出。
 * 档位按网格的列数与行数给：小 1×1，宽 2×1，高 1×2，大 2×2。
 * 一档多少点由设计合同与宿主的网格算，模型不管。
 */
@Serializable(with = WidgetSizeSerializer::class)
enum class WidgetSize {
    SMALL,
    WIDE,
    TALL,
    LARGE,
    ;

    /** 序列化用的键。 */
    val key: String get() = name.lowercase()

    companion object {
        /** 认不出的档位回退到这一档。 */
        val FALLBACK: WidgetSize = SMALL
    }
}

/**
 * [WidgetSize] 的读写。
 *
 * 读的时候宽容：认不出的档位回退到 [WidgetSize.FALLBACK]，不抛异常。
 * 抛异常会让整个组件掉队（见 `WorkbenchStore.decodeList`），
 * 而尺寸认不出时缩小一档显示就好，没有理由丢掉用户排好的卡片。
 */
internal object WidgetSizeSerializer : KSerializer<WidgetSize> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("WidgetSize", PrimitiveKind.STRING)

    override fun serialize(encoder: Encoder, value: WidgetSize) {
        encoder.encodeString(value.key)
    }

    override fun deserialize(decoder: Decoder): WidgetSize {
        val raw = decoder.decodeString().trim().lowercase()
        return WidgetSize.entries.firstOrNull { it.key == raw } ?: WidgetSize.FALLBACK
    }
}

/**
 * 首页网格上的一块组件。
 *
 * [kind] 是字符串，不是枚举。组件目录还没定，枚举会逼着模型提前认识每一种组件。
 * 宿主认不出的种类要显示一张占位卡片，不能丢：丢掉就丢了用户排好的位置。
 *
 * [settings] 是组件自己的配置。模型不解释它，组件实现自己读。
 *
 * [column] 与 [row] 是网格左上角的显式位置。两者必须同时有效。
 * 任一值为 [WIDGET_AUTOMATIC_POSITION] 时，宿主按列表顺序自动摆放。
 */
@Serializable
data class WidgetInstance(
    @SerialName("id") val id: String,
    @SerialName("kind") val kind: String,
    @SerialName("size") val size: WidgetSize = WidgetSize.FALLBACK,
    @SerialName("settings") val settings: JsonObject = JsonObject(emptyMap()),
    @SerialName("column") val column: Int = WIDGET_AUTOMATIC_POSITION,
    @SerialName("row") val row: Int = WIDGET_AUTOMATIC_POSITION,
) {
    /** 显式位置是否完整。只有一个坐标时不当作有效位置。 */
    fun hasGridPosition(): Boolean = column >= 0 && row >= 0

    /** 返回带显式网格位置的一份副本。 */
    fun withGridFrame(size: WidgetSize, column: Int, row: Int): WidgetInstance = copy(
        size = size,
        column = column,
        row = row,
    )

    fun normalized(): WidgetInstance {
        val positioned = hasGridPosition()
        return copy(
            id = id.trim().take(MAX_ID_LENGTH),
            kind = kind.trim().take(MAX_KIND_LENGTH),
            column = if (positioned) column else WIDGET_AUTOMATIC_POSITION,
            row = if (positioned) row else WIDGET_AUTOMATIC_POSITION,
        )
    }
}

/**
 * 挂帘里的一个工作区。
 *
 * [id] 是稳定标识。内置工作区的 id 等于种类的键（见 [PaneKind.defaultId]）。
 * 用户改工作区的名字，id 不变，所以设置与顺序都跟着走。
 *
 * [title] 与 [icon] 空串表示「用内置的」。用户改过名之后才写进文件。
 * 这样换语言时，没改过名的工作区跟着合同换名字。
 *
 * [settings] 是这个工作区自己的设置。模型不解释它，页面实现自己读。
 */
@Serializable
data class PaneInstance(
    @SerialName("id") val id: String,
    @SerialName("kind") val kind: PaneKind,
    @SerialName("title") val title: String = "",
    @SerialName("icon") val icon: String = "",
    @SerialName("isHidden") val isHidden: Boolean = false,
    @SerialName("settings") val settings: JsonObject = JsonObject(emptyMap()),
) {
    /**
     * 内置与否由种类推导，不单独存字段。
     * 存成字段会出现「种类是内置，字段说不是」这种自相矛盾的文件。
     */
    val isBuiltin: Boolean get() = kind.isBuiltin

    fun normalized(): PaneInstance = copy(
        id = id.trim().take(MAX_ID_LENGTH),
        title = title.trim().take(MAX_TITLE_LENGTH),
        icon = icon.trim().take(MAX_ID_LENGTH),
    )

    companion object {
        /**
         * 造一个内置工作区。
         *
         * 只定 id 与种类。名字与图标由宿主按 [PaneKind.titleCopyKey] 去读，
         * 不写进配置。
         */
        fun builtin(kind: PaneKind): PaneInstance = PaneInstance(id = kind.defaultId, kind = kind)
    }
}

/**
 * 工作台配置。落在 `workbench.json` 里。
 *
 * 首页不是工作区，所以它不在 [panes] 里。首页固定在 tab bar 左端
 * （ADR-0002 决策 4），它的组件单独放在 [homeWidgets]。
 */
@Serializable
data class WorkbenchConfig(
    @SerialName("schemaVersion") val schemaVersion: Int = WORKBENCH_SCHEMA_VERSION,
    @SerialName("panes") val panes: List<PaneInstance> = defaultPanes(),
    @SerialName("homeWidgets") val homeWidgets: List<WidgetInstance> = defaultWidgets(),
) {
    /** tab bar 只画可见的工作区。助手与设置由固定入口打开，不参与页签导航。 */
    val visiblePanes: List<PaneInstance>
        get() = panes.filterNot { it.isHidden || !it.kind.appearsInWorkbenchNavigation }

    fun pane(id: String): PaneInstance? = panes.firstOrNull { it.id == id }

    /**
     * 加一个工作区。
     *
     * 达到上限、id 重复、或者要塞进来的是内置工作区时，原样返回。
     * 内置工作区只能由 [defaults] 产生，用户加不出来。
     */
    fun addPane(pane: PaneInstance): WorkbenchConfig {
        val candidate = pane.normalized()
        if (candidate.id.isEmpty()) return this
        if (candidate.isBuiltin) return this
        if (panes.any { it.id == candidate.id }) return this
        if (panes.size >= MAX_PANES) return this
        return copy(panes = panes + candidate)
    }

    /**
     * 删一个工作区。
     *
     * 内置工作区删不掉，原样返回。界面要按 [PaneInstance.isBuiltin]
     * 先把删除按钮置灰，不要靠这里兜底。
     */
    fun removePane(id: String): WorkbenchConfig {
        val target = pane(id) ?: return this
        if (target.isBuiltin) return this
        return copy(panes = panes.filterNot { it.id == id })
    }

    /** 显示或隐藏一个工作区。内置工作区只能隐藏，不能删除。 */
    fun setPaneHidden(id: String, hidden: Boolean): WorkbenchConfig =
        copy(panes = panes.map { if (it.id == id) it.copy(isHidden = hidden) else it })

    /** 改工作区的名字。传空串表示恢复内置名字。 */
    fun renamePane(id: String, title: String): WorkbenchConfig =
        copy(panes = panes.map { if (it.id == id) it.copy(title = title.trim().take(MAX_TITLE_LENGTH)) else it })

    /** 把工作区移到指定下标。下标越界时夹到两端。找不到 id 时原样返回。 */
    fun movePane(id: String, toIndex: Int): WorkbenchConfig {
        val from = panes.indexOfFirst { it.id == id }
        if (from < 0) return this
        val reordered = panes.toMutableList()
        val moved = reordered.removeAt(from)
        reordered.add(toIndex.coerceIn(0, reordered.size), moved)
        return copy(panes = reordered)
    }

    /**
     * 把配置修回能用的样子。
     *
     * 坏文件不一定要整份丢掉。能修的修，修不了的才丢：
     *
     * 1. 丢掉 id 空白的条目。
     * 2. 内置工作区的 id 改成由种类定。手改过的错位 id 会和补回来的条目撞车。
     * 3. 丢掉占用内置 id 的自建工作区。
     * 4. id 重复时留第一个。
     * 5. 删除 schema 1 的历史截图工作区。
     * 6. 补回缺失的当前内置工作区。补在末尾：原位置已经丢了，插在中间会打乱用户排好的顺序。
     * 7. 工作区超过 [MAX_PANES] 时先丢自建工作区，内置的一个都不丢。
     * 8. 组件丢掉 id 或种类为空的，id 重复时留第一个，超过 [MAX_WIDGETS] 时留前 24 个。
     * 9. 组件的列与行必须成对出现；只有一个坐标时退回自动摆放。
     */
    fun normalized(): WorkbenchConfig = copy(
        schemaVersion = WORKBENCH_SCHEMA_VERSION,
        panes = normalizedPanes(panes),
        homeWidgets = normalizedWidgets(homeWidgets),
    )

    companion object {
        /** 工作区数量上限。见 ADR-0002 决策 5。 */
        const val MAX_PANES = 12

        /** 首页组件数量上限。只用来挡住坏文件，正常使用到不了这个数。 */
        const val MAX_WIDGETS = 24

        /**
         * 本版默认配置。
         *
         * Swift 侧不能调 `WorkbenchConfig()`：默认参数不导出到 Swift。
         * 所以默认值只从这一个入口取。与 `ConfigStore.defaults()` 同一个理由。
         */
        fun defaults(): WorkbenchConfig = WorkbenchConfig()
    }
}

/**
 * 六个当前内置工作区，按需求文档第 5 节的顺序。
 *
 * 顺序在所有平台上一致：Now、Agent、Clipboard、Files、Devices、Settings。
 * Screenshots 是 schema 1 的历史种类，不再进入默认配置。
 * 用户可以改顺序，默认值只有这一份。
 */
fun defaultPanes(): List<PaneInstance> = PaneKind.entries
    .filter { it.isCurrentBuiltin }
    .map { PaneInstance.builtin(it) }

/**
 * 首页默认的六块组件，按需求文档第 6 节的顺序与档位。
 *
 * 空首页只有一块提示，用户第一次打开会以为坏了。所以默认摆满，
 * 用户不想要哪块就在编辑模式里删掉。
 *
 * [WidgetInstance.kind] 是字符串：组件目录还没定，模型不提前认识每一种组件。
 * 这里的六个键由宿主的组件目录解释，认不出的键宿主显示占位卡片。
 */
fun defaultWidgets(): List<WidgetInstance> = listOf(
    WidgetInstance(id = "w-clock", kind = "w-clock", size = WidgetSize.WIDE),
    WidgetInstance(id = "w-battery", kind = "w-battery", size = WidgetSize.SMALL),
    WidgetInstance(id = "w-transfer", kind = "w-transfer", size = WidgetSize.WIDE),
    WidgetInstance(id = "w-actions", kind = "w-actions", size = WidgetSize.TALL),
    WidgetInstance(id = "w-shots", kind = "w-shots", size = WidgetSize.LARGE),
    WidgetInstance(id = "w-devices", kind = "w-devices", size = WidgetSize.SMALL),
)

private fun normalizedPanes(panes: List<PaneInstance>): List<PaneInstance> {
    val reservedIds = PaneKind.entries.filter { it.isBuiltin }.mapTo(HashSet()) { it.defaultId }
    val seen = LinkedHashSet<String>()
    val cleaned = panes.asSequence()
        .map(PaneInstance::normalized)
        // schema 1 的截图工作区由文件区接替。迁移时直接删除，不再补回。
        .filterNot { it.kind == PaneKind.SCREENSHOTS }
        // 内置工作区的 id 由种类定，不认文件里写的那个。
        // 不这么改的话，手改出来的错位 id 会和补回来的内置工作区撞车。
        .map { if (it.isBuiltin) it.copy(id = it.kind.defaultId) else it }
        .filter { it.id.isNotEmpty() }
        // 自建工作区的 id 由宿主生成，正常撞不上保留 id。
        .filter { it.isBuiltin || it.id !in reservedIds }
        .filter { seen.add(it.id) }
        .toMutableList()

    val present = cleaned.mapTo(HashSet()) { it.kind }
    for (kind in PaneKind.entries) {
        if (kind.isCurrentBuiltin && kind !in present) cleaned += PaneInstance.builtin(kind)
    }

    val builtins = cleaned.count { it.isBuiltin }
    val room = (WorkbenchConfig.MAX_PANES - builtins).coerceAtLeast(0)
    val keptCustomIds = cleaned.asSequence()
        .filterNot { it.isBuiltin }
        .map { it.id }
        .take(room)
        .toHashSet()

    return cleaned.filter { it.isBuiltin || it.id in keptCustomIds }
}

private fun normalizedWidgets(widgets: List<WidgetInstance>): List<WidgetInstance> {
    val seen = LinkedHashSet<String>()
    return widgets.asSequence()
        .map(WidgetInstance::normalized)
        .filter { it.id.isNotEmpty() && it.kind.isNotEmpty() }
        .filter { seen.add(it.id) }
        .take(WorkbenchConfig.MAX_WIDGETS)
        .toList()
}
