///|
/// One portable demo state: composition, never a second counter value.
pub struct SpacingModel {
  priv counter : Model
  priv expanded : Bool
} derive(Eq, @debug.Debug)

///|
pub fn SpacingModel::new() -> SpacingModel {
  { counter: Model::new(), expanded: false, }
}

///|
pub fn SpacingModel::counter(self : SpacingModel) -> Model {
  self.counter
}

///|
pub fn SpacingModel::value(self : SpacingModel) -> Int {
  self.counter.value()
}

///|
pub fn SpacingModel::update_counter(
  self : SpacingModel,
  action : @core.SemanticAction,
) -> SpacingModel {
  { ..self, counter: self.counter.update(action), }
}

///|
pub fn SpacingModel::update(
  self : SpacingModel,
  action : @core.SemanticAction,
) -> SpacingModel {
  match action {
    @core.Activate(key) if key == @core.NodeKey::new("spacing-toggle") =>
      { ..self, expanded: !self.expanded, }
    _ => self.update_counter(action)
  }
}

///|
pub extend SpacingModel with Eq::{equal, not_equal}

///|
pub extend SpacingModel with @debug.Debug::{to_repr}

///|
pub fn SpacingModel::expanded(self : SpacingModel) -> Bool {
  self.expanded
}

///|
/// Both backends import this exact view and model update. Spacing is application
/// state; the host drivers observe it but never keep a second copy.
pub fn SpacingModel::view(self : SpacingModel) -> @core.View {
  let outer = @core.StackSpacing::new(
    if self.expanded {
      @core.Twelve
    } else {
      @core.Zero
    },
    if self.expanded {
      @core.Sixteen
    } else {
      @core.Four
    },
  )
  let inner = @core.StackSpacing::new(
    if self.expanded {
      @core.Sixteen
    } else {
      @core.Four
    },
    if self.expanded {
      @core.Eight
    } else {
      @core.Zero
    },
  )
  @core.column_with_spacing(
    @core.NodeKey::new("counter"),
    [
      @core.text(@core.NodeKey::new("heading"), "Shared <stack>"),
      @core.text(@core.NodeKey::new("value"), "Count: \{self.counter.value()}"),
      @core.row_with_spacing(
        @core.NodeKey::new("actions"),
        [
          @core.button(@core.NodeKey::new("increment"), "Increment"),
          @core.button(@core.NodeKey::new("spacing-toggle"), "Spacing"),
        ],
        inner,
      ),
      @core.card(@core.NodeKey::new("preview"), [
        @core.text(@core.NodeKey::new("card-label"), "Fixed Card"),
      ]),
    ],
    outer,
  )
}

///|
/// Font-independent fixture: empty padded stacks supply intrinsic boxes. The
/// browser fixture host shrink-wraps; stretched cross-axis sizes are host-owned.
pub fn spacing_geometry_view() -> @core.View {
  @core.column_with_spacing(
    @core.NodeKey::new("fixed"),
    [
      @core.row_with_spacing(
        @core.NodeKey::new("fixed-row"),
        [
          @core.column_with_spacing(
            @core.NodeKey::new("box-a"),
            [],
            @core.StackSpacing::new(@core.Zero, @core.Eight),
          ),
          @core.column_with_spacing(
            @core.NodeKey::new("box-b"),
            [],
            @core.StackSpacing::new(@core.TwentyFour, @core.Sixteen),
          ),
        ],
        @core.StackSpacing::new(@core.Twelve, @core.Four),
      ),
      @core.card(@core.NodeKey::new("fixed-card"), [
        @core.column_with_spacing(
          @core.NodeKey::new("box-c"),
          [],
          @core.StackSpacing::new(@core.Zero, @core.Zero),
        ),
      ]),
    ],
    @core.StackSpacing::new(@core.Eight, @core.TwentyFour),
  )
}
