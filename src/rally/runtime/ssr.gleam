import lustre/element.{type Element}

/// Render a Lustre element tree to a full HTML document string.
/// Used server-side during SSR.
pub fn render_to_html(element: Element(msg)) -> String {
  element.to_document_string(element)
}
