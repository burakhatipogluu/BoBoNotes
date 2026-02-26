import SwiftUI

/// Responsive layout metrics computed from window width.
/// Three size categories adapt UI chrome for different screen sizes.
struct LayoutMetrics {

    enum SizeCategory {
        case compact   // < 900px  (13" MacBook narrow window)
        case regular   // 900–1399px (standard working size)
        case large     // ≥ 1400px (large monitors)
    }

    let windowWidth: CGFloat

    var sizeCategory: SizeCategory {
        if windowWidth < 900 { return .compact }
        if windowWidth < 1400 { return .regular }
        return .large
    }

    // MARK: - Toolbar

    var toolbarHeight: CGFloat {
        switch sizeCategory {
        case .compact:  return 26
        case .regular:  return 28
        case .large:    return 30
        }
    }

    var toolbarIconSize: CGFloat {
        switch sizeCategory {
        case .compact:  return 12
        case .regular:  return 13
        case .large:    return 14
        }
    }

    var toolbarButtonSize: CGSize {
        switch sizeCategory {
        case .compact:  return CGSize(width: 22, height: 20)
        case .regular:  return CGSize(width: 26, height: 22)
        case .large:    return CGSize(width: 28, height: 24)
        }
    }

    // MARK: - Tab Bar

    var tabBarHeight: CGFloat {
        switch sizeCategory {
        case .compact:  return 26
        case .regular:  return 30
        case .large:    return 32
        }
    }

    var tabIconSize: CGFloat {
        switch sizeCategory {
        case .compact:  return 14
        case .regular:  return 18
        case .large:    return 20
        }
    }

    var tabHorizontalPadding: CGFloat {
        switch sizeCategory {
        case .compact:  return 8
        case .regular:  return 12
        case .large:    return 14
        }
    }

    // MARK: - Status Bar

    var statusBarHeight: CGFloat {
        switch sizeCategory {
        case .compact:  return 20
        case .regular:  return 22
        case .large:    return 24
        }
    }

    // MARK: - Panel Widths (HSplitView constraints)

    var workspaceMinWidth: CGFloat {
        switch sizeCategory {
        case .compact:  return 60
        case .regular:  return 80
        case .large:    return 100
        }
    }

    var workspaceIdealWidth: CGFloat {
        switch sizeCategory {
        case .compact:  return 70
        case .regular:  return 90
        case .large:    return 120
        }
    }

    var workspaceMaxWidth: CGFloat {
        switch sizeCategory {
        case .compact:  return 300
        case .regular:  return 500
        case .large:    return 600
        }
    }

    var editorMinWidth: CGFloat {
        switch sizeCategory {
        case .compact:  return 200
        case .regular:  return 300
        case .large:    return 400
        }
    }

    var functionListMinWidth: CGFloat {
        switch sizeCategory {
        case .compact:  return 120
        case .regular:  return 160
        case .large:    return 180
        }
    }

    var functionListIdealWidth: CGFloat {
        switch sizeCategory {
        case .compact:  return 150
        case .regular:  return 220
        case .large:    return 260
        }
    }

    var functionListMaxWidth: CGFloat {
        switch sizeCategory {
        case .compact:  return 250
        case .regular:  return 400
        case .large:    return 500
        }
    }

    var splitPaneMinWidth: CGFloat {
        switch sizeCategory {
        case .compact:  return 150
        case .regular:  return 200
        case .large:    return 250
        }
    }

    var diffPaneMinWidth: CGFloat {
        switch sizeCategory {
        case .compact:  return 150
        case .regular:  return 200
        case .large:    return 250
        }
    }

    // MARK: - UI Font Sizes (chrome only, NOT editor font)

    var uiFontSize: CGFloat {
        switch sizeCategory {
        case .compact:  return 10
        case .regular:  return 11
        case .large:    return 12
        }
    }

    var uiFontSizeSmall: CGFloat {
        switch sizeCategory {
        case .compact:  return 9
        case .regular:  return 10
        case .large:    return 11
        }
    }

    var uiFontSizeMedium: CGFloat {
        switch sizeCategory {
        case .compact:  return 11
        case .regular:  return 12
        case .large:    return 13
        }
    }

    // MARK: - Panel Headers

    var paneHeaderHeight: CGFloat {
        switch sizeCategory {
        case .compact:  return 22
        case .regular:  return 24
        case .large:    return 28
        }
    }

    var diffHeaderHeight: CGFloat {
        switch sizeCategory {
        case .compact:  return 24
        case .regular:  return 28
        case .large:    return 30
        }
    }

    // MARK: - Tree Indent

    var treeIndentPerLevel: CGFloat {
        switch sizeCategory {
        case .compact:  return 12
        case .regular:  return 16
        case .large:    return 18
        }
    }
}

// MARK: - Environment Key

struct LayoutMetricsKey: EnvironmentKey {
    static let defaultValue = LayoutMetrics(windowWidth: 1200)
}

extension EnvironmentValues {
    var layoutMetrics: LayoutMetrics {
        get { self[LayoutMetricsKey.self] }
        set { self[LayoutMetricsKey.self] = newValue }
    }
}
