///|
fn main {
  let buttons : Array[String] = []
  let shells : Array[String] = []
  for theme in [@theme.Light, @theme.Dark] {
    let button_tokens : Array[String] = []
    for (name, color) in theme.button_colors().entries() {
      button_tokens.push(
        "\"\{name}\":[\{color.red()},\{color.green()},\{color.blue()}]",
      )
    }
    buttons.push("\"\{theme.name()}\":{\{button_tokens.join(",")}}")
    let shell_tokens : Array[String] = []
    for (name, color) in theme.shell_colors().entries() {
      shell_tokens.push(
        "\"\{name}\":[\{color.red()},\{color.green()},\{color.blue()}]",
      )
    }
    shells.push("\"\{theme.name()}\":{\{shell_tokens.join(",")}}")
  }
  println(
    "{\"buttons\":{\{buttons.join(",")}},\"shell\":{\{shells.join(",")}}}",
  )
}
