class App::Services::Session < App::Services::Base

  def login
    email = params[:email].to_s.strip.downcase
    user  = User.find(email: email, active: true)

    if user && user.password && user.password == params[:password].to_s
      user.last_logged_in_at  = Time.now
      user.current_session_id = CurrentUser.encoded_token(user)
      user.save
      ActivityLog.record!(action: 'login', entity: user, user: user, details: "Signed in as #{user.role}")
      return_success(token: user.current_session_id, info: user.as_pos)
    else
      # Response stays generic (no user enumeration); the log keeps the detail.
      ActivityLog.record!(action: 'login_failed', user: user, details: "Failed login attempt for #{email}")
      return_errors!("Invalid email or password")
    end
  rescue => e
    App.logger.error(e.message)
    App.logger.error(e.backtrace)
    return_errors!("Login failed")
  end

end
