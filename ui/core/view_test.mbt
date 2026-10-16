///|
test "views snapshot child arrays and expose only copies" {
  let first = @core.text(@core.NodeKey::new("first"), "Original")
  let children = [first]
  let tree = @core.column(@core.NodeKey::new("root"), children)
  children[0] = @core.text(@core.NodeKey::new("replacement"), "Changed")
  children.push(@core.button(@core.NodeKey::new("extra"), "Extra"))
  assert_eq(tree.children(), [first])
  let exposed = tree.children()
  exposed.clear()
  assert_eq(tree.children(), [first])
  let nested = @core.row(@core.NodeKey::new("outer"), [tree])
  nested.children()[0].children().clear()
  assert_eq(nested.children()[0].children(), [first])
}

///|
test "constructors preserve semantic kind and literal label" {
  let key = @core.NodeKey::new("save")
  let button = @core.button(
    key,
    "<Save & continue>",
    disabled=true,
    loading=true,
  )
  assert_eq(button.key(), key)
  assert_eq(button.key().value(), "save")
  assert_eq(button.kind(), @core.Button)
  assert_eq(button.label(), "<Save & continue>")
  assert_true(button.disabled())
  assert_true(button.loading())
  assert_eq(button.children(), [])
  let text = @core.text(@core.NodeKey::new("caption"), "日本語")
  assert_eq(text.kind(), @core.Text)
  assert_eq(text.label(), "日本語")
  assert_true(!text.disabled() && !text.loading())
  assert_eq(@core.row(key, []).kind(), @core.Row)
  assert_eq(@core.column(key, []).kind(), @core.Column)
}
