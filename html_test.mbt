///|
fn expect_render(html : @yami_kumo.Html) -> String {
  match @yami_kumo.render_html(html) {
    Ok(output) => output
    Err(_) => ""
  }
}

///|
fn expect_attr(name : String, value : String) -> @yami_kumo.Attribute {
  match @yami_kumo.attr(name, value) {
    Ok(attribute) => attribute
    Err(_) =>
      match @yami_kumo.attr("data-test", "invalid-test-fallback") {
        Ok(attribute) => attribute
        Err(_) =>
          match @yami_kumo.attr("data-test", "fallback") {
            Ok(attribute) => attribute
            Err(_) => abort("a valid test attribute must be accepted")
          }
      }
  }
}

///|
test "HTML text and attributes are escaped" {
  let node = @yami_kumo.element("span", [expect_attr("title", "<x> \" & '")], [
    @yami_kumo.text("<script>alert(1)</script>"),
  ])
  match node {
    Ok(html) =>
      assert_eq(
        expect_render(html),
        "<span title=\"&lt;x&gt; &quot; &amp; &#x27;\">&lt;script&gt;alert(1)&lt;/script&gt;</span>",
      )
    Err(_) => assert_true(false)
  }
}

///|
test "unsafe element and attribute names are rejected" {
  assert_true(@yami_kumo.attr("onclick", "alert(1)") is Err(_))
  assert_true(@yami_kumo.attr("ARIA-label", "Name") is Err(_))
  assert_true(@yami_kumo.attr("aria-label\n", "Name") is Err(_))
  assert_true(
    @yami_kumo.element("script", [], [@yami_kumo.text("alert(1)")]) is Err(_),
  )
  assert_true(
    @yami_kumo.element("textarea", [], [@yami_kumo.text("Draft")]) is Ok(_),
  )
  assert_true(@yami_kumo.element("canvas", [], []) is Ok(_))
}

///|
test "unsafe URL schemes are rejected case-insensitively" {
  assert_true(@yami_kumo.attr("href", "JaVaScRiPt:alert(1)") is Err(_))
  assert_true(@yami_kumo.attr("src", "data:text/html,hello") is Err(_))
  assert_true(@yami_kumo.attr("href", "/settings") is Ok(_))
}

///|
test "button uses the pinned Kumo primary classes and safe content" {
  let html = @yami_kumo.button(
    @yami_kumo.text("Save & continue"),
    variant=Primary,
    size=Lg,
    attrs=[expect_attr("id", "save")],
  )
  let output = expect_render(html)
  assert_true(
    output.contains(
      "h-10 gap-2 rounded-lg px-4 text-base relative overflow-hidden bg-(--kumo-button-emphasis-bg)",
    ),
  )
  assert_true(output.contains("yk-kumo-button-emphasis-primary"))
  assert_true(!output.contains("style="))
  assert_true(output.contains("Save &amp; continue"))
  assert_true(output.contains("id=\"save\""))
}

///|
test "disabled Kumo button keeps its native disabled state" {
  let output = expect_render(
    @yami_kumo.button(@yami_kumo.text("Unavailable"), disabled=true),
  )
  assert_true(output.contains("disabled=\"\""))
  assert_true(output.contains("cursor-not-allowed opacity-50"))
}

///|
test "Kumo input labels and errors link to the control" {
  let output = expect_render(
    @yami_kumo.input(
      id="email",
      size=Lg,
      label=@yami_kumo.text("Email"),
      description=@yami_kumo.text("Used for account notices"),
      error=@yami_kumo.text("Enter a valid email"),
      placeholder="name@example.com",
      required=true,
      attrs=[expect_attr("id", "email")],
    ),
  )
  assert_true(output.contains("for=\"email\""))
  assert_true(output.contains("id=\"email\""))
  assert_true(output.contains("aria-labelledby=\"email-label\""))
  assert_true(output.contains("aria-describedby=\"email-error\""))
  assert_true(!output.contains("aria-invalid"))
  assert_true(!output.contains("id=\"email-description\""))
  assert_true(output.contains("!ring-kumo-danger"))
  assert_true(output.contains("Enter a valid email"))
  assert_true(!output.contains("Used for account notices"))
}

///|
test "disabled Kumo input preserves the upstream disabled data state" {
  let output = expect_render(
    @yami_kumo.input(
      id="managed-account",
      label=@yami_kumo.text("Managed account"),
      disabled=true,
    ),
  )
  assert_true(output.contains("data-disabled=\"\""))
  assert_true(output.contains("disabled=\"\""))
}

///|
test "pre-filled Kumo fields start filled and can compare against initial value" {
  let output = expect_render(
    @yami_kumo.input(
      id="workspace-name",
      label=@yami_kumo.text("Workspace name"),
      description=@yami_kumo.text("Visible to teammates"),
      attrs=[expect_attr("value", "Northstar")],
    ),
  )
  assert_true(output.contains("value=\"Northstar\""))
  assert_true(output.contains("data-filled=\"\""))
  assert_true(!output.contains("data-dirty"))
  assert_true(!output.contains("data-touched"))
}

///|
test "multiple labeled inputs keep unique ids and valid references" {
  let first = @yami_kumo.input(
    id="email",
    label=@yami_kumo.text("Email"),
    description=@yami_kumo.text("Account notices"),
    error=@yami_kumo.text("Enter a valid address"),
  )
  let second = @yami_kumo.input(
    id="display-name",
    label=@yami_kumo.text("Display name"),
    description=@yami_kumo.text("Shown to teammates"),
  )
  let output = expect_render(@yami_kumo.fragment([first, second]))
  assert_true(output.contains("for=\"email\""))
  assert_true(output.contains("aria-labelledby=\"email-label\""))
  assert_true(output.contains("aria-describedby=\"email-error\""))
  assert_true(output.contains("id=\"email-error\""))
  assert_true(output.contains("for=\"display-name\""))
  assert_true(output.contains("aria-describedby=\"display-name-description\""))
  assert_true(output.contains("id=\"display-name-description\""))
  assert_true(!output.contains("yk-input\""))
}

///|
test "unlabeled Kumo input keeps its caller supplied id" {
  let output = expect_render(
    @yami_kumo.input(id="workspace-search", placeholder="Search", attrs=[
      expect_attr("aria-label", "Search workspace"),
    ]),
  )
  assert_true(output.contains("<input id=\"workspace-search\""))
  assert_true(output.contains("placeholder=\"Search\""))
  assert_true(output.contains("aria-label=\"Search workspace\""))
  assert_true(!output.contains("<label"))
  assert_true(!output.contains("yk-kumo-input-field"))
}

///|
test "Kumo text and layered cards use pinned classes" {
  let heading = expect_render(
    @yami_kumo.text_component(
      @yami_kumo.text("Project settings"),
      variant=Heading,
      size=Lg,
      as_element="h1",
    ),
  )
  assert_true(
    heading.contains("<h1 class=\"text-kumo-default font-semibold text-xl\">"),
  )
  let card = expect_render(
    @yami_kumo.layer_card(
      @yami_kumo.fragment([
        @yami_kumo.layer_card_secondary(@yami_kumo.text("Workspace")),
        @yami_kumo.layer_card_primary(@yami_kumo.text("Team settings")),
      ]),
      layered=true,
    ),
  )
  assert_true(
    card.contains("bg-kumo-elevated text-base ring ring-kumo-hairline"),
  )
  assert_true(card.contains("font-medium text-kumo-subtle"))
  assert_true(card.contains("ring-kumo-fill"))
}

///|
test "app shell keeps localized close labels and explicit state" {
  let html = @yami_kumo.app_shell(
    @yami_kumo.text("Brand"),
    @yami_kumo.text("Main"),
    sidebar=@yami_kumo.text("Navigation"),
    context_panel=@yami_kumo.text("Details"),
    close_workspace_navigation_label="ナビゲーションを閉じる",
    close_context_panel_label="詳細を閉じる",
    mobile_sidebar_open=true,
  )
  let output = expect_render(html)
  assert_true(
    output.contains("aria-label=\"ナビゲーションを閉じる\""),
  )
  assert_true(output.contains("aria-label=\"詳細を閉じる\""))
  assert_true(output.contains("data-mobile-sidebar-open=\"true\""))
  assert_true(output.contains("id=\"yk-mobile-navigation\""))
}
