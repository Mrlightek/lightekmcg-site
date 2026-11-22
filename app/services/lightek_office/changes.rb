module LightekOffice
  module Changes
    class Conflict < StandardError
      attr_reader :current

      def initialize(file)
        @current = Changes.snapshot(file)
        super('Another editor changed this range. Your draft is still available.')
      end
    end

    module_function

    def snapshot(file)
      {version: file.lock_version, title: file.title, content: file.content, rich_text: file.rich_text?, editor: editor(file)}
    end

    def history(file)
      revisions(file).order(version: :desc).limit(50).map do |revision|
        {version: revision.version, title: revision.title, editor: revision.editor_name, saved_at: revision.created_at.iso8601}
      end
    end

    def revisions(file) = Revision.where(file: file)

    def editor(file)
      file.respond_to?(:editor_name) ? file.editor_name : file.editor.full_name
    end

    # The caller holds the record lock. Persist the old revision and the new content atomically.
    def write!(file, attributes, expected:, merge: false)
      version = Integer(expected.to_s, 10)
      raise ArgumentError, 'Keep the file within 64 KB.' if attributes.fetch(:content).to_s.bytesize > Content::MAX_BYTES

      if version != file.lock_version
        base = revisions(file).find_by(version: version) if merge
        content = if base && base.rich_text? == file.rich_text? && base.rich_text? == attributes[:rich_text]
          merge_text(base.content, file.content, attributes[:content], rich_text: file.rich_text?)
        end
        raise Conflict, file unless content

        attributes = attributes.merge(content: content)
      end

      previous = snapshot(file)
      file.assign_attributes(attributes)
      file.validate!
      return previous unless file.has_changes_to_save?

      revisions(file).create!(version: previous.fetch(:version), title: previous.fetch(:title),
        content: previous.fetch(:content), rich_text: previous.fetch(:rich_text), editor_name: previous.fetch(:editor))
      file.save!
      snapshot(file)
    end

    def restore!(file, version:, expected:, actor:)
      revision = revisions(file).find_by!(version: Integer(version.to_s, 10))
      write!(file, actor.merge(title: revision.title, content: revision.content, rich_text: revision.rich_text?), expected: expected)
    end

    def merge_text(base, current, draft, rich_text: false)
      return current if draft == base
      return draft if current == base || current == draft

      before, after = [change_range(base, current), change_range(base, draft)].sort_by(&:first)
      return if before.first == after.first || before[1] > after.first
      return if rich_text && ![before, after].all? { |range| text_only_range?(base, range) }

      start, finish, replacement = before
      next_start, next_end, next_replacement = after
      base[0...start] + replacement + base[finish...next_start] + next_replacement + base[next_end..]
    end

    def text_only_range?(base, range)
      start, finish, replacement = range
      prefix = base[0...start]
      in_tag = (prefix.rindex('<') || -1) > (prefix.rindex('>') || -1)
      in_entity = prefix.match?(/&[#[:alnum:]]*\z/)
      !in_tag && !in_entity && !replacement.match?(/[<>&]/) && !base[start...finish].match?(/[<>&]/)
    end

    def change_range(base, modified)
      original_chars = base.chars
      updated_chars = modified.chars
      first = 0
      limit = [original_chars.size, updated_chars.size].min
      first += 1 while first < limit && original_chars[first] == updated_chars[first]
      tail = 0
      tail += 1 while tail < limit - first && original_chars[-tail - 1] == updated_chars[-tail - 1]
      [first, original_chars.size - tail, updated_chars[first...(updated_chars.size - tail)].join]
    end
  end
end
