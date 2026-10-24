# Calibration's one quiet offer: accept writes the pref, decline silences
# the offer forever. The commune has no row, so both are no-ops there.
class CalibrationsController < ApplicationController
  def create
    current_enlistee&.accept_keep_simple!
    redirect_back_or_to root_path
  end

  def destroy
    current_enlistee&.decline_keep_simple!
    redirect_back_or_to root_path
  end
end
