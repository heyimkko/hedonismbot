class ApplicationController < ActionController::Base
  protect_from_forgery

  protected
  
  def current_user
    @current_user ||= User.find(session[:user_id]) if session[:user_id]
  end

  def current_user=(user)
    @current_user = user
  end

  helper_method :current_user
end
