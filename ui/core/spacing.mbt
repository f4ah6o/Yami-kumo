///|
/// Closed logical-pixel spacing values. Arbitrary numbers (including negative,
/// nonfinite and unsupported values) cannot enter the shared layout contract.
pub(all) enum SpacingToken {
  Zero
  Four
  Eight
  Twelve
  Sixteen
  TwentyFour
} derive(Eq, @debug.Debug)

///|
pub fn SpacingToken::pixels(self : SpacingToken) -> Double {
  match self {
    Zero => 0.0
    Four => 4.0
    Eight => 8.0
    Twelve => 12.0
    Sixteen => 16.0
    TwentyFour => 24.0
  }
}

///|
/// Uniform padding and direct-child gap for a plain Row or Column only.
pub struct StackSpacing {
  priv gap : SpacingToken
  priv padding : SpacingToken
} derive(Eq, @debug.Debug)

///|
pub fn StackSpacing::new(
  gap : SpacingToken,
  padding : SpacingToken,
) -> StackSpacing {
  { gap, padding, }
}

///|
pub fn StackSpacing::gap(self : StackSpacing) -> SpacingToken {
  self.gap
}

///|
pub fn StackSpacing::padding(self : StackSpacing) -> SpacingToken {
  self.padding
}

///|
/// Explicit spacing; sizing/alignment remain host-owned. See shared-stack-spacing.md.
/// There is no setter that can override a fixed Card or decorate a leaf.
pub fn row_with_spacing(
  key : NodeKey,
  children : Array[View],
  spacing : StackSpacing,
) -> View {
  { ..row(key, children), spacing: Some(spacing), }
}

///|
pub fn column_with_spacing(
  key : NodeKey,
  children : Array[View],
  spacing : StackSpacing,
) -> View {
  { ..column(key, children), spacing: Some(spacing), }
}

///|
/// None retains legacy host spacing or the separate fixed Card contract.
pub fn View::spacing(self : View) -> StackSpacing? {
  self.spacing
}

///|
pub extend SpacingToken with Eq::{equal, not_equal}

///|
pub extend SpacingToken with @debug.Debug::{to_repr}

///|
pub extend StackSpacing with Eq::{equal, not_equal}

///|
pub extend StackSpacing with @debug.Debug::{to_repr}
