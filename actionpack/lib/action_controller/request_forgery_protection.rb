module ActionController #:nodoc:
  class InvalidAuthenticityToken < ActionControllerError #:nodoc:
  end

  module RequestForgeryProtection
    def self.included(base)
      base.class_eval do
        class_inheritable_accessor :request_forgery_protection_options
        self.request_forgery_protection_options = {}
        helper_method :form_authenticity_token
      end
      base.extend(ClassMethods)
    end
    
    module ClassMethods
      # Protect a controller's actions from CSRF attacks by ensuring that all forms are coming from the current web application, not 
      # a forged link from another site. This is done by embedding a token based on the session (which an attacker wouldn't know) in 
      # all forms and Ajax requests generated by Rails and then verifying the authenticity of that token in the controller. Only
      # HTML/JavaScript requests are checked, so this will not protect your XML API (presumably you'll have a different authentication
      # scheme there anyway). Also, GET requests are not protected as these should be indempotent anyway.
      #
      # You turn this on with the #protect_from_forgery method, which will perform the check and raise 
      # an ActionController::InvalidAuthenticityToken if the token doesn't match what was expected. And it will add 
      # a _authenticity_token parameter to all forms that are automatically generated by Rails. You can customize the error message 
      # given through public/422.html.
      #
      # Learn more about CSRF (Cross-Site Request Forgery) attacks:
      #
      # * http://isc.sans.org/diary.html?storyid=1750
      # * http://en.wikipedia.org/wiki/Cross-site_request_forgery
      #
      # Keep in mind, this is NOT a silver-bullet, plug 'n' play, warm security blanket for your rails application.
      # There are a few guidelines you should follow:
      # 
      # * Keep your GET requests safe and idempotent.  More reading material:
      #   * http://www.xml.com/pub/a/2002/04/24/deviant.html
      #   * http://www.w3.org/Protocols/rfc2616/rfc2616-sec9.html#sec9.1.1
      # * Make sure the session cookies that Rails creates are non-persistent.  Check in Firefox and look for "Expires: at end of session"
      #
      # If you need to construct a request yourself, but still want to take advantage of forgery protection, you can grab the 
      # authenticity_token using the form_authenticity_token helper method and make it part of the parameters yourself.
      #
      # Example:
      #
      #   class FooController < ApplicationController
      #     # uses the cookie session store (then you don't need a separate :secret)
      #     protect_from_forgery :except => :index
      #
      #     # uses one of the other session stores that uses a session_id value.
      #     protect_from_forgery :secret => 'my-little-pony', :except => :index
      #   end
      #
      # Valid Options:
      #
      # * <tt>:only/:except</tt> - passed to the before_filter call.  Set which actions are verified.
      # * <tt>:secret</tt> - Custom salt used to generate the form_authenticity_token.
      #   Leave this off if you are using the cookie session store.
      # * <tt>:digest</tt> - Message digest used for hashing.  Defaults to 'SHA1'
      def protect_from_forgery(options = {})
        self.request_forgery_protection_token ||= :authenticity_token
        before_filter :verify_authenticity_token, :only => options.delete(:only), :except => options.delete(:except)
        request_forgery_protection_options.update(options)
      end
    end

    protected
      # The actual before_filter that is used.  Modify this to change how you handle unverified requests.
      def verify_authenticity_token
        verified_request? || raise(ActionController::InvalidAuthenticityToken)
      end
      
      # Returns true or false if a request is verified.  Checks:
      #
      # * is the format restricted?  By default, only HTML and AJAX requests are checked.
      # * is it a GET request?  Gets should be safe and idempotent
      # * Does the form_authenticity_token match the given _token value from the params?
      def verified_request?
        request_forgery_protection_token.nil? ||
          request.method == :get              ||
          !verifiable_request_format?         ||
          form_authenticity_token == params[request_forgery_protection_token]
      end
    
      def verifiable_request_format?
        request.format.html? || request.format.js?
      end
    
      # Sets the token value for the current session.  Pass a :secret option in #protect_from_forgery to add a custom salt to the hash.
      def form_authenticity_token
        @form_authenticity_token ||= if request_forgery_protection_options[:secret]
          authenticity_token_from_session_id
        else
          authenticity_token_from_cookie_session
        end
      end
      
      # Generates a unique digest using the session_id and the CSRF secret.
      def authenticity_token_from_session_id
        key = if request_forgery_protection_options[:secret].respond_to?(:call)
          request_forgery_protection_options[:secret].call(@session)
        else
          request_forgery_protection_options[:secret]
        end
        digest = request_forgery_protection_options[:digest] ||= 'SHA1'
        OpenSSL::HMAC.hexdigest(OpenSSL::Digest::Digest.new(digest), key.to_s, session.session_id.to_s)
      end
      
      # No secret was given, so assume this is a cookie session store.
      def authenticity_token_from_cookie_session
        session[:csrf_id] ||= CGI::Session.generate_unique_id
        session.dbman.generate_digest(session[:csrf_id])
      end
  end
end