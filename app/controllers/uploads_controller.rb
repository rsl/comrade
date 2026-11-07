# Serves reader-attached images: /uploads/<key>.<ext>. The key is the
# SHA256 of the stored bytes (ImageStore); the filename grammar is
# enforced against the 24-hex + allowlist pattern before any path is
# built, so only storage/uploads/<hex>.<ext> can ever be served.
class UploadsController < ApplicationController
  def show
    served = Comrade::ImageStore.serve(params[:filename])
    return head :not_found unless served

    # A key's bytes can never change: cache hard across turns, devices.
    expires_in 30.days, public: true
    send_file served[:path], type: served[:content_type], disposition: 'inline'
  end
end
