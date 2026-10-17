///|
test "closed spacing tokens are exact finite nonnegative values" {
  let tokens = [
    @core.Zero,
    @core.Four,
    @core.Eight,
    @core.Twelve,
    @core.Sixteen,
    @core.TwentyFour,
  ]
  let values = [0.0, 4.0, 8.0, 12.0, 16.0, 24.0]
  for i in 0..<tokens.length() {
    assert_eq(tokens[i].pixels(), values[i])
    let spacing = @core.StackSpacing::new(tokens[i], tokens[5 - i])
    assert_eq(spacing.gap(), tokens[i])
    assert_eq(spacing.padding(), tokens[5 - i])
  }
}

///|
test "explicit stacks copy arrays and cannot override fixed Card or leaves" {
  let key = @core.NodeKey::new("stack")
  let spacing = @core.StackSpacing::new(@core.Zero, @core.TwentyFour)
  let children = [@core.text(@core.NodeKey::new("text"), "<literal>&")]
  let row = @core.row_with_spacing(key, children, spacing)
  let column = @core.column_with_spacing(key, children, spacing)
  children.clear()
  assert_eq(row.children().length(), 1)
  row.children().clear()
  assert_eq(row.children().length(), 1)
  assert_eq(row.kind(), @core.Row)
  assert_eq(column.kind(), @core.Column)
  assert_eq(row.spacing(), Some(spacing))
  assert_eq(column.spacing(), Some(spacing))
  assert_true(!row.is_card() && !column.is_card())
  for
    view in [
      @core.row(key, []),
      @core.column(key, []),
      @core.card(key, []),
      @core.text(key, "x"),
      @core.button(key, "x"),
    ] {
    assert_eq(view.spacing(), None)
  }
}
