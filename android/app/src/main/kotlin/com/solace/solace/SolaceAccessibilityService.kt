package com.solace.solace

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent

/**
 * 无障碍可选模块骨架（默认关闭；核心功能不依赖它，关掉不影响任何核心体验）。
 *
 * 刻意不做的事，一律没有实现：
 * - 不读屏：配置里 canRetrieveWindowContent=false，本类也不取任何节点；
 * - 不执行手势：配置里 canPerformGestures=false；
 * - 不在任何节点上调 performAction，不自动点确认/支付/提交；
 * - onAccessibilityEvent 刻意空实现，不读事件内容。
 *
 * 服务只负责“存在”（满足系统对无障碍模块的注册要求）；
 * 真正的“打开指定 App 的指定页面”由 MainActivity 的 accessibility 通道
 * 用普通 Intent 做，且只在用户明确指令 + 模块开关开启时执行，
 * 打开后停在目标页面即止，不再做任何后续操作。
 */
class SolaceAccessibilityService : AccessibilityService() {

    companion object {
        @Volatile
        var connected = false
            private set
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        connected = true
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // 刻意空实现：不读事件内容，不做任何自动化操作。
    }

    override fun onInterrupt() {
        connected = false
    }

    override fun onDestroy() {
        connected = false
        super.onDestroy()
    }
}
