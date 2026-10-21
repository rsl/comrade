# frozen_string_literal: true

# Vendored from Fractured Atlas's unifractured gem
# (github.com/fracturedatlas — private), author's own copy with permission.

module RuboCop
  module Cop
    module Layout
      # Identical to Layout/MultilineMethodArgumentLineBreaks, except that
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
