///|
fn main {
  let themes : Array[String] = []
  for theme in [@theme.Light, @theme.Dark] {
    let tokens : Array[String] = []
    for (name, color) in theme.button_colors().entries() {
      tokens.push(
        "\"\{name}\":[\{color.red()},\{color.green()},\{color.blue()}]",
      )
    }
    themes.push("\"\{theme.name()}\":{\{tokens.join(",")}}")
  }
  println("{\{themes.join(",")}}")
}
