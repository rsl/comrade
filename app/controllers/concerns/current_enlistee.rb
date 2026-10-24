# Presence, not auth: the token cookie says which enlistee this browser
# is, and no cookie means the commune — nil, everywhere, with no special
# case. The tailnet is the perimeter; the cookie only remembers.
module CurrentEnlistee
  extend ActiveSupport::Concern

  TOKEN_COOKIE = 'comrade_token'
  SEEN_COOKIE = 'comrade_seen'

  included do
    helper_method :current_enlistee, :enlistee_seen?, :identity_chip
  end

  def current_enlistee
    return @current_enlistee if defined?(@current_enlistee)

    @current_enlistee = Comrade::Enlistee.find_by(token: cookies[TOKEN_COOKIE])
  end

  # Enlist or claim: this browser now IS this comrade. 400 days — the
  # longest expiry browsers honor (Chrome caps there); server-set and
  # httpOnly, so Safari's script-cookie caps don't apply.
  def enlist_as(enlistee)
    cookies[TOKEN_COOKIE] = { value: enlistee.token,
expires: 400.days,
      httponly: true, }
    @current_enlistee = enlistee
  end

  # Step out: the browser returns to the commune. The comrade row keeps
  # everything; only presence is dropped.
  def step_out
    cookies.delete(TOKEN_COOKIE)
    @current_enlistee = nil
  end

  # The enlistment panel is a first-run door, shown once; the sidebar
  # keeps it reachable forever after.
  def enlistee_seen?
    cookies[SEEN_COOKIE].present?
  end

  def mark_enlistment_seen
    cookies[SEEN_COOKIE] = { value: '1', expires: 400.days, httponly: true }
  end

  # What the chip says: the name, or the commune when anon. The identity
  # banner's JS reads the same value — names are unique, so the name is
  # a complete identity marker.
  def identity_chip
    current_enlistee&.name || 'the commune'
  end
end
