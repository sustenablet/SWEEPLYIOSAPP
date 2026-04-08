//
//  SweeplyWIdgetsBundle.swift
//  SweeplyWIdgets
//
//  Created by Joao Leite on 4/8/26.
//

import WidgetKit
import SwiftUI

@main
struct SweeplyWIdgetsBundle: WidgetBundle {
    var body: some Widget {
        NextJobWidget()
        TodayScheduleWidget()
    }
}
