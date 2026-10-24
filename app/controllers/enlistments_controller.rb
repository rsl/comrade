# The one identity door: enlisting and claiming are the same act — type
# a name; a new one joins, an existing one is claimed. Stepping out
# clears presence only; the row and its conversations keep existing.
class EnlistmentsController < ApplicationController
  # First-run dismiss: the panel has been seen; the sidebar door remains.
  def new
    mark_enlistment_seen
    redirect_back_or_to root_path
  end

  def create
    name = params[:name].to_s.strip
    if name.present?
      enlist_as(Comrade::Enlistee.enlist!(name))
      @identity_changed = true
    end
    redirect_back_or_to root_path
  rescue ActiveRecord::RecordInvalid
    # A refused name (taken race, too long) just lands you back where you
    # were, still on the commune — the input's maxlength and the rarity of
    # the race make this the whole feedback path for now.
    redirect_back_or_to root_path
  end

  def destroy
    step_out
    @identity_changed = true
    redirect_to root_path
  end
end
