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

///|
test "Card is an additive noninteractive immutable Column decoration" {
  let key = @core.NodeKey::new("card")
  let literal = @core.text(@core.NodeKey::new("literal"), "<b>& literal")
  let children = [literal]
  let card = @core.card(key, children)
  children.clear()
  assert_eq(card.kind(), @core.Column)
  assert_true(card.is_card())
  assert_true(!@core.column(key, [literal]).is_card())
  assert_eq(card.children(), [literal])
  card.children().clear()
  assert_eq(card.children()[0].label(), "<b>& literal")
  assert_eq(card.label(), "")
  assert_true(!card.disabled() && !card.loading())
  // Deliberately exhaustive: existing consumers must remain source-compatible.
  assert_eq(
    match card.kind() {
      @core.Text => 0
      @core.Button => 1
      @core.Column => 2
      @core.Row => 3
      @core.AppShell => 4
      @core.TextField => 5
      @core.Dialog => 6
    },
    2,
  )
}

///|
test "TextField props are immutable and expose the committed value" {
  let props = @core.TextFieldProps::new(
    "日本語",
    "名前",
    description="表示名",
    error=Some("必須です"),
    required=true,
    revision=7UL,
  )
  let field = @core.text_field(@core.NodeKey::new("name"), props)
  assert_eq(field.kind(), @core.TextField)
  assert_eq(field.label(), "名前")
  assert_eq(field.text_field_revision(), 7UL)
  assert_eq(field.children(), [])
  match field.text_field_props() {
    Some(value) => {
      assert_eq(value.value(), "日本語")
      assert_eq(value.description(), "表示名")
      assert_eq(value.error().unwrap(), "必須です")
      assert_true(value.required())
      assert_true(!value.read_only())
    }
    None => abort("TextField props missing")
  }
  let read_only = @core.TextFieldProps::new("x", "x", read_only=true)
  let field = @core.text_field(@core.NodeKey::new("readonly"), read_only)
  assert_true(field.text_field_props().unwrap().read_only())
}

///|
test "Dialog props stay application-owned and immutable" {
  let props = @core.DialogProps::new(
    true,
    "Save changes?",
    dismissible=false,
    initial_focus=Some(@core.NodeKey::new("cancel")),
  )
  let children = [@core.button(@core.NodeKey::new("cancel"), "Cancel")]
  let modal = @core.dialog(@core.NodeKey::new("confirm"), props, children)
  children.clear()
  assert_eq(modal.kind(), @core.Dialog)
  assert_eq(modal.label(), "Save changes?")
  assert_true(modal.dialog_open())
  assert_eq(modal.children().length(), 1)
  match modal.dialog_props() {
    Some(value) => {
      assert_true(!value.dismissible())
      assert_eq(value.initial_focus().unwrap().value(), "cancel")
    }
    None => abort("Dialog props missing")
  }
  let closed = @core.dialog(
    @core.NodeKey::new("closed"),
    @core.DialogProps::new(false, "Closed"),
    [],
  )
  assert_true(!closed.dialog_open())
}
