# frozen_string_literal: true

module RuboCop
  module Cop
    module Layout
      # A backslash-newline is a line break the parser erases: strings
      # concatenate invisibly and expressions continue invisibly, so the
      # reader sees two lines that are one. This codebase breaks inside
      # the parens or brackets instead, and joins strings with `<<` or a
      # heredoc — visible joins at the join site.
      # Heredoc bodies are exempt: text content may legitimately end a
      # line with a backslash.
      class RejectLineContinuation < Base
        MSG = 'Do not continue a line with a backslash — break inside the brackets.'

        def on_new_investigation
          return unless processed_source.ast

          bodies = heredoc_body_ranges
          processed_source.lines.each_with_index do |line, index|
            next unless line.rstrip.end_with?('\\')

            number = index + 1
            next if bodies.any? { |range| range.cover?(number) }

            add_offense(offense_range(line, number), severity: :convention)
          end
        end

        private

        def heredoc_body_ranges
          processed_source.ast.each_node(:str, :dstr, :xstr)
            .select { |node| node.loc.respond_to?(:heredoc_end) && node.loc.heredoc_end }
            .map { |node| (node.loc.expression.last_line + 1)..(node.loc.heredoc_end.line - 1) }
        end

        def offense_range(line, number)
          column = line.rstrip.length - 1
          begin_pos = processed_source.buffer.line_range(number).begin_pos + column
          Parser::Source::Range.new(processed_source.buffer, begin_pos, begin_pos + 1)
        end
      end
    end
  end
end
