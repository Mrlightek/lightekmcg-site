# frozen_string_literal: true
require 'cgi'
require 'uri'
module NevaehHelpHelper
  def nevaeh_help_button(topic, label: 'Help')
    content_tag(:button, 'i', type: 'button', class: 'nv-info', data: {nevaeh_help: topic}, aria: {label: "#{label}: tutorial", haspopup: 'dialog'})
  end
  def nevaeh_loss_plot(history)
    values = Array(history).select { |value| value.is_a?(Numeric) && value.finite? }.last(50)
    return ''.html_safe if values.empty?
    low, high = values.minmax; range = [high - low, 0.001].max
    points = values.each_with_index.map { |value, index| "#{40 + index * 540.0 / [values.length - 1, 1].max},#{135 - (value - low) * 110.0 / range}" }.join(' ')
    parts = [content_tag(:title, 'Online training loss by epoch'),
      content_tag(:line, '', x1: 40, y1: 140, x2: 580, y2: 140, stroke: '#51445e'),
      content_tag(:polyline, '', points: points, fill: 'none', stroke: '#bca5ff', 'stroke-width' => 3),
      content_tag(:text, high.round(3).to_s, x: 0, y: 28, fill: '#b8acc9', 'font-size' => 12),
      content_tag(:text, low.round(3).to_s, x: 0, y: 140, fill: '#b8acc9', 'font-size' => 12),
      content_tag(:text, "Epoch 1 → #{values.length}", x: 40, y: 169, fill: '#b8acc9', 'font-size' => 12)]
    content_tag(:svg, safe_join(parts), viewBox: '0 0 600 180', role: 'img', aria: {label: 'Online training loss by epoch'}, class: 'nf-loss-chart')
  end
  def nevaeh_document_inline(text)
    escaped = ERB::Util.html_escape(text.to_s).to_s
    escaped = escaped.gsub(/`([^`]+)`/, '<code>\\1</code>').gsub(/\*\*([^*]+)\*\*/, '<strong>\\1</strong>')
    escaped = escaped.gsub(/\[([^\]]+)\]\(([^)]+)\)/) do
      label = CGI.unescapeHTML(Regexp.last_match(1)); destination = CGI.unescapeHTML(Regexp.last_match(2))
      uri = URI.parse(destination) rescue nil
      if uri&.scheme == 'https' && uri.host.present?
        content_tag(:a, label, href: destination, target: '_blank', rel: 'noopener noreferrer')
      elsif destination.match?(%r{\A[a-zA-Z0-9_./-]+\.(?:md|markdown|txt)\z}) && respond_to?(:main_app)
        content_tag(:a, label, href: main_app.employee_software_library_path(q: File.basename(destination, '.*').tr('_-', ' ')))
      else
        ERB::Util.html_escape(label)
      end
    end
    escaped.html_safe
  end
  # Source is escaped before structural markup. Repository HTML/ERB never runs.
  def nevaeh_document_html(body)
    code = false; out = []; paragraph = []; lines = body.to_s.lines.map(&:chomp); index = 0
    flush = -> { unless paragraph.empty?; out << content_tag(:p, nevaeh_document_inline(paragraph.join(' '))); paragraph.clear; end }
    cells = ->(line) { line.strip.sub(/\A\|/, '').sub(/\|\z/, '').split('|').map(&:strip) }
    while index < lines.length
      line = lines[index]
      if line.start_with?('```')
        flush.call; code = !code
        out << (code ? '<pre><code>'.html_safe : '</code></pre>'.html_safe)
      elsif code
        out << ERB::Util.html_escape(line + "\n")
      elsif line.include?('|') && lines[index + 1]&.match?(/\A\s*\|?\s*:?-{3,}/)
        flush.call
        header = content_tag(:tr, safe_join(cells.call(line).map { |cell| content_tag(:th, nevaeh_document_inline(cell)) }))
        rows = []; index += 2
        while index < lines.length && lines[index].include?('|') && lines[index].present?
          rows << content_tag(:tr, safe_join(cells.call(lines[index]).map { |cell| content_tag(:td, nevaeh_document_inline(cell)) }))
          index += 1
        end
        out << content_tag(:div, content_tag(:table, safe_join([content_tag(:thead, header), content_tag(:tbody, safe_join(rows))])), class: 'nc-table-wrap')
        next
      elsif (match = /\A(\#{1,6})\s+(.+)/.match(line))
        flush.call; out << content_tag("h#{match[1].length}", nevaeh_document_inline(match[2]))
      elsif line.blank?
        flush.call
      elsif line.start_with?('- ', '* ')
        flush.call; out << content_tag(:p, nevaeh_document_inline(line.sub(/\A[-*] /, '• ')), class: 'sl-bullet')
      else
        paragraph << line
      end
      index += 1
    end
    flush.call
    out << '</code></pre>'.html_safe if code
    safe_join(out, "\n")
  end
end
