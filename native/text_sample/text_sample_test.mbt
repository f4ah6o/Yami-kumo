///|
test "text sample view keeps the field value and status in sync" {
  let sample = @text_sample.TextSample::new()
  let view = sample.view()
  assert_eq(view.kind(), @view.Column)
  assert_eq(view.children().length(), 3)
  assert_eq(view.children()[0].key(), @text_sample.text_sample_status())
  assert_eq(view.children()[0].label(), "No submission")
  assert_eq(view.children()[1].key(), @text_sample.text_sample_field())
  assert_eq(
    match view.children()[1].text_field_props() {
      Some(props) => props.value()
      None => ""
    },
    "",
  )
  assert_true(
    sample.apply(
      @view.TextChanged(@text_sample.text_sample_field(), "にほんご"),
    ),
  )
  assert_eq(sample.value(), "にほんご")
  assert_false(
    sample.apply(@view.TextChanged(@view.NodeKey::new("other"), "ignored")),
  )
  assert_true(sample.apply(@view.Submitted(@text_sample.text_sample_field())))
  assert_eq(sample.submitted(), Some("にほんご"))
  assert_eq(sample.view().children()[0].label(), "Submitted: にほんご")
  assert_false(sample.apply(@view.Activate(@view.NodeKey::new("other"))))
  assert_true(sample.apply(@view.Activate(@text_sample.text_sample_submit())))
  assert_false(sample.apply(@view.Dismissed(@text_sample.text_sample_field())))
}
