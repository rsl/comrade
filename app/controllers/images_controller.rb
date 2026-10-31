# Serves proxied images: /img/<key>?p=<url>. The key is the truncated
# HMAC of the source url — unsigned or mistyped requests are rejected
# before any fetch happens, so the proxy serves only urls comrade itself
# surfaced. Copies cache under storage/images/ (ImageProxy).
class ImagesController < ApplicationController
  def show
    source = params[:p].to_s
    return head :bad_request unless Comrade::ImageProxy.authorized?(source, params[:key])

    served = Comrade::ImageProxy.retrieve(source)
    return head :bad_gateway unless served

    # Thumbnails recur across turns and devices: cache hard. The bytes
    # for a given signed url never change.
    expires_in 30.days, public: true
    send_file served[:path], type: served[:content_type], disposition: 'inline'
  end
end
