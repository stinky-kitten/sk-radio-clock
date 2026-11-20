//
//  MSFEpistemicSecond.h
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-10-05.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

struct MSFEpistemicSecond: Equatable {
  var a: MSFEpistemicValue<Bool>
  var b: MSFEpistemicValue<Bool>

  init() {
    a = MSFEpistemicValue()
    b = MSFEpistemicValue()
  }
}
