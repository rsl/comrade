# frozen_string_literal: true

module RuboCop
  module Cop
    module Layout
      # A project-local variant of Layout/MultilineMethodArgumentLineBreaks:
      # calls whose arguments include a lambda literal (-> { ... }) are
      # exempt. A lambda argument carries a code body rather than a data
      # value, so those calls keep their signature and block opener on one
      # line and break inside the block:
      #   # good
      #   scope :published, -> {
      #     where.not(published_at: nil)
      #   }
      # Data arguments still break one per line:
      #   # bad
      #   foo arg_1, arg_2,
      #     arg_3
      #   # good
      #   foo(
      #     arg_1,
      #     arg_2,
      #     arg_3
      #   )
      class MultilineMethodArgumentLineBreaksExceptLambdas < MultilineMethodArgumentLineBreaks
        def on_send(node)
          return if node.arguments.any? { |argument| exempt?(argument) }

          super
        end
        alias on_csend on_send

        private

        def exempt?(argument)
          argument.block_type? || argument.block_pass_type?
        end
      end
    end
  end
end
