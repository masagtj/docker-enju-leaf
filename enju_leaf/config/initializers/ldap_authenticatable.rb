require 'net/ldap'
require 'devise/strategies/authenticatable'


module Devise
  module Strategies
    class LdapAuthenticatable < Authenticatable
      def authenticate!
        Rails.logger.info "ldap auth : in LDAP Auth method"

        if params[:user]
          Rails.logger.info "ldap auth : username=#{username}"

          if username.start_with?("enju")
            # bypass ldap auth if user is admin
            Rails.logger.info "ldap auth : bypass ldap auth"

            resource = valid_password? && mapping.to.find_for_database_authentication(authentication_hash)

            if validate(resource){ resource.valid_password?(password) }
              resource.after_database_authentication
              success!(resource)
            elsif !halted?
              fail(:invalid)
            end

            return
          end

          #create_user
          Rails.logger.info "#{username}@#{LDAP_CONFIG["ldap"]["domain"]}"

          #LDAPサーバーに接続
          conn = Net::LDAP.new :host => LDAP_CONFIG["ldap"]["host"],
                        #:encryption => :simple_tls,
                        :port => LDAP_CONFIG["ldap"]["port"],
                        :base => LDAP_CONFIG["ldap"]["basedn"],
                        :auth => { :username => "#{username}@#{LDAP_CONFIG["ldap"]["domain"]}",
                                    :password => password,
                                    :method => :simple }
          Rails.logger.info "conn completed"
          #create_user
          #認証処理
          if conn.bind
            Rails.logger.info "bind completed"
            logged_in = true
            #属性取得
            entries = Hash.new
            conn.open do |ldap|
              Rails.logger.info "open completed"
              filter = Net::LDAP::Filter.eq(LDAP_CONFIG["ldap"]["bind"]["username"], username)
              attrs = ["sAMAccountName", "displayName", "mail"]
              res = ldap.search(:filter => filter, :attributes => attrs) { |item|
                Rails.logger.info  "#{item.sAMAccountName.first}: #{item.displayName.first} (#{item.mail.first})"
              }
              #get_ldap_response(ldap)

              unless res
                fail(:invalid_login)
              else
                resource = mapping.to.find_for_database_authentication(authentication_hash)
                unless resource
                  Rails.logger.info "Create User"
                  resource = create_user(res.first) && mapping.to.find_for_database_authentication(authentication_hash)
                else
                  Rails.logger.info "Update User"
                  resource.password = user_data[:password]
                  resource.password_confirmation = user_data[:password_confirmation]
                  resource.save
                end

                resource.after_database_authentication
                success!(resource)
              end

            end

          else
            fail(:invalid_login)
          end

        end
      end

      def get_ldap_response(ldap)
        msg = "Response Code: #{ ldap.get_operation_result.code }, Message: #{ ldap.get_operation_result.message }"

        raise msg unless ldap.get_operation_result.code == 0
      end

      def new_profile
        profile = Profile.new
        profile.user_group = UserGroup.first
        profile.library = Library.real.first
        profile.locale = I18n.default_locale.to_s
        profile
      end

      def create_user(ldap_user)

        user = User.new
        user.username = optimizename
        user.email = ldap_user[LDAP_CONFIG["ldap"]["bind"]["mail"]].first
        #user.full_name = ldap_user[LDAP_CONFIG["ldap"]["bind"]["full_name"]].first
        user.password = user_data[:password]
        user.password_confirmation = user_data[:password_confirmation]
        #user.confirm!
        user.role = Role.where(name: 'User').first
        user.save!

        profile = new_profile
        profile.full_name = ldap_user[LDAP_CONFIG["ldap"]["bind"]["full_name"]].first
        profile.user_number = optimizename
        profile.save_checkout_history = true
        profile.user = user
        profile.save!
      end

      def username
        params[:user][:username]
      end

      # バリデーションを通らないので暫定処置
      def optimizename
        params[:user][:username].gsub(/(-|\.)/) { '_' }
      end

      def password
        params[:user][:password]
      end

      def user_data
        {:username => optimizename, :password => password, :password_confirmation => password}
      end

      def authentication_hash
        #{:username => params[:user][:username]}
        {:username => optimizename }
      end
    end
  end
end

Warden::Strategies.add(:ldap_authenticatable, Devise::Strategies::LdapAuthenticatable)
