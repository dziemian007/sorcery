module Sorcery
  module Controller
    module Submodules
      # This submodule helps you login users from external auth providers such as Twitter.
      # This is the controller part which handles the http requests and tokens passed between the app and the provider.
      module External
        def self.included(base)
          base.send(:include, InstanceMethods)
          Config.module_eval do
            class << self
              attr_reader :external_providers                           # external providers like twitter.
              attr_accessor :ca_file                                    # path to ca_file. By default use a internal ca-bundle.crt.

              def merge_external_defaults!
                @defaults.merge!(:@external_providers => [],
                                 :@ca_file => File.join(File.expand_path(File.dirname(__FILE__)), 'external/protocols/certs/ca-bundle.crt'))
              end

              def external_providers=(providers)
                providers.each do |provider|
                  include Providers.const_get(provider.to_s.split("_").map {|p| p.capitalize}.join(""))
                end
              end
            end
            merge_external_defaults!
          end
        end

        module InstanceMethods
          protected

          # sends user to authenticate at the provider's website.
          # after authentication the user is redirected to the callback defined in the provider config
          def login_at(provider, args = {})
            @provider = Config.send(provider)
            if @provider.has_callback?
              redirect_to @provider.login_url(params,session)
            else
              #@provider.login(args)
            end
          end

          # tries to login the user from provider's callback
          def login_from(provider)
            @provider = Config.send(provider)
            @provider.process_callback(params,session)
            @user_hash = @provider.get_user_hash
            Rails.logger.info "#############################"
            Rails.logger.info @user_hash.inspect
            if user = user_class.load_from_provider(provider,@user_hash[:uid].to_s)
              if user.name.blank? && @user_hash[:user_info].has_key?("name")
                user.update_attribute(:name, @user_hash[:user_info]["name"])
              end
              if (user.email.blank? || user.email.index("@").nil?) && @user_hash[:user_info].has_key?("email")
                user.update_attribute(:email, @user_hash[:user_info]["email"])
              end
              if user.gender.blank? && @user_hash[:user_info].has_key?("gender")
                user.update_attribute(:gender, @user_hash[:user_info]["gender"])
              end
              if user.birthday.blank? && @user_hash[:user_info].has_key?("birthday")
                user.update_attribute(:birthday, Date.strptime(@user_hash[:user_info]["birthday"], "%m/%d/%Y"))
              end
              reset_session
              auto_login(user)
              user
            end
          end

          # login from provider if user have regular account
          def login_regular_from(provider)
            @provider = Config.send(provider)
            @user_hash = @provider.get_user_hash
            Rails.logger.info "#############################"
            Rails.logger.info @user_hash.inspect
            config = user_class.sorcery_config
            @user = user_class.find_by_email(@user_hash[:user_info]["email"])
            auth = user_class.load_from_provider(provider,@user_hash[:uid].to_s)
            if @user && !auth
              user_class.transaction do
                user_class.sorcery_config.authentications_class.create!({config.authentications_user_id_attribute_name => @user.id, config.provider_attribute_name => provider, config.provider_uid_attribute_name => @user_hash[:uid]})
              end
              reset_session
              auto_login(@user)
              @user
            end
          end

          # get provider access account
          def access_token(provider)
            @provider = Config.send(provider)
            @provider.access_token
          end

          # this method automatically creates a new user from the data in the external user hash.
          # The mappings from user hash fields to user db fields are set at controller config.
          # If the hash field you would like to map is nested, use slashes. For example, Given a hash like:
          #
          #   "user" => {"name"=>"moishe"}
          #
          # You will set the mapping:
          #
          #   {:username => "user/name"}
          #
          # And this will cause 'moishe' to be set as the value of :username field.
          # Note: Be careful. This method skips validations model.
          def create_from(provider)
            provider = provider.to_sym
            @provider = Config.send(provider)
            @user_hash = @provider.get_user_hash
            Rails.logger.info "#############################"
            Rails.logger.info @user_hash.inspect
            config = user_class.sorcery_config
            attrs = {}
            @provider.user_info_mapping.each do |k,v|
              if (varr = v.split("/")).size > 1
                attribute_value = varr.inject(@user_hash[:user_info]) {|hsh,v| hsh[v] } rescue nil
                if attribute_value && k == "birthday"
                  attribute_value = Date.strptime(attribute_value, "%m/%d/%Y")
                end
                attribute_value.nil? ? attrs : attrs.merge!(k => attribute_value)
              else
                if k.to_s == "birthday"
                  attrs.merge!(k => Date.strptime(@user_hash[:user_info][v], "%m/%d/%Y"))
                else
                  attrs.merge!(k => @user_hash[:user_info][v])
                end
              end
            end
            user_class.transaction do
              @user = user_class.new()
              attrs.each do |k,v|
                @user.send(:"#{k}=", v)
              end
              @user.save(:validate => false)
              user_class.sorcery_config.authentications_class.create!({config.authentications_user_id_attribute_name => @user.id, config.provider_attribute_name => provider, config.provider_uid_attribute_name => @user_hash[:uid]})
            end
            @user
          end
        end
      end
    end
  end
end
