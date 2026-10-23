class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # A stale URL (conversation deleted, old tab) lands home instead of a 404.
  rescue_from ActiveRecord::RecordNotFound do
    redirect_to root_path, alert: "That conversation is gone."
  end
end
