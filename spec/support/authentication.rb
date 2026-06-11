# frozen_string_literal: true

module Authentication
  def authenticate!(request, user)
    request.headers["Authorization"] = "Bearer #{jwt_for(user)}"
  end

  def jwt_for(user)
    payload = {
        "account_id" => user.id,
        "e"          => user.email,
        "exp"        => 1.hour.from_now.to_i
    }
    JWT.encode(payload, Rails.application.credentials.jwt_secret, "HS256")
  end

  # Automatically injects the Authorization header on all subsequent
  # HTTP requests within the current example.
  def sign_in(user)
    @_auth_headers = {"Authorization" => "Bearer #{jwt_for(user)}"}
  end

  # Override request helpers to inject auth headers when signed in.
  %i[get post put patch delete head].each do |method|
    define_method(method) do |path, **kwargs|
      if @_auth_headers
        kwargs[:headers] = (kwargs[:headers] || {}).merge(@_auth_headers)
      end
      super(path, **kwargs)
    end
  end
end
