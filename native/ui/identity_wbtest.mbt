///|
test "native epoch probes preserve markers and liveness for aliases and distinct cells" {
  for left_live in [false, true] {
    for right_live in [false, true] {
      for left_marker in [false, true] {
        for right_marker in [false, true] {
          let left = fresh_epoch()
          let right = fresh_epoch()
          left.live = left_live
          right.live = right_live
          left.marker = left_marker
          right.marker = right_marker
          let copied = left
          for _ in 0..<3 {
            assert_true(same_epoch(left, left))
            assert_true(same_epoch(left, copied))
            assert_true(same_epoch(copied, left))
            assert_true(same_epoch(right, right))
            assert_eq(left.marker, left_marker)
            assert_eq(right.marker, right_marker)
            assert_eq(copied.marker, left_marker)
            assert_eq(left.live, left_live)
            assert_eq(right.live, right_live)
            assert_true(!same_epoch(left, right))
            assert_eq(left.marker, left_marker)
            assert_eq(right.marker, right_marker)
            assert_eq(left.live, left_live)
            assert_eq(right.live, right_live)
            assert_true(!same_epoch(right, copied))
            assert_eq(left.marker, left_marker)
            assert_eq(right.marker, right_marker)
            assert_eq(copied.live, left_live)
            assert_eq(right.live, right_live)
          }
        }
      }
    }
  }
}
