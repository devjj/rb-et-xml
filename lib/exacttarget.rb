module ExactTarget
  
  API_URI = 'https://api.dc1.exacttarget.com/integrate.aspx'
  
  class ExactTargetError < StandardError; end;
  
  class Base
    def initialize(options = {})
      @user     = options[:user] || nil
      @password = options[:password] || nil
      
      @debug    = options[:debug] || false
    end
    
    def online?
      doc = ''
      xml = Builder::XmlMarkup.new(:target => doc, :indent => 1)
      
      xml.instruct!
      xml.exacttarget do |xml|
        xml.authorization do |xml|
          xml.username @user
          xml.password @password
        end
        xml.system do |xml|
          xml.system_name 'diagnostics'
          xml.action 'Ping'
        end
      end
      
      response = post(doc)
      
      result = parse_diagnostic_response(response.body)
      
      result
    end
    
    def add_subscriber(email_address, list_id, attributes = {})
      doc = ''
      xml = Builder::XmlMarkup.new(:target => doc, :indent => 1)
      
      xml.instruct!
      xml.exacttarget do |xml|
        xml.authorization do |xml|
          xml.username @user
          xml.password @password
        end
        xml.system do |xml|
          xml.system_name 'subscriber'
          xml.action 'add'
          xml.search_type 'listid'
          xml.search_value list_id
          xml.search_value2
          xml.values do |xml|
            xml.Email__Address email_address
            xml.status 'active'
            attributes.keys.each do |key|
              formatted_key_name = format_attribute(key)
              value = attributes[key]
              
              xml.tag! formatted_key_name, value
            end
          end
        end
      end
      
      response = post(doc)
      
      result = parse_add_subscriber_response(response.body)
      
      result
    end
    
    def delete_subscriber_from_list(email_address, list_id)
      doc = ''
      xml = Builder::XmlMarkup.new(:target => doc, :indent => 1)
      
      xml.instruct!
      xml.exacttarget do |xml|
        xml.authorization do |xml|
          xml.username @user
          xml.password @password
        end
        xml.system do |xml|
          xml.system_name 'subscriber'
          xml.action 'delete'
          xml.search_type 'listid'
          xml.search_value list_id
          xml.search_value2 email_address
        end
      end

      response = post(doc)
      
      result = parse_delete_subscriber_response(response.body)
      
      result
    end

    def delete_subscriber(email_address, subscriber_id)
      doc = ''
      xml = Builder::XmlMarkup.new(:target => doc, :indent => 1)
      
      xml.instruct!
      xml.exacttarget do |xml|
        xml.authorization do |xml|
          xml.username @user
          xml.password @password
        end
        xml.system do |xml|
          xml.system_name 'subscriber'
          xml.action 'delete'
          xml.search_type 'subid'
          xml.search_value subscriber_id
          xml.search_value2
        end
      end

      response = post(doc)
      
      result = parse_delete_subscriber_response(response.body)
      
      result
    end
    
    def send_email_to_subscriber(options = {})
      email_id = options[:email_id]
      subscriber_id = options[:subscriber_id]
      email_address = options[:email_address]
      
      if email_id.blank? || (email_address.blank? && subscriber_id.blank?)
        raise ExactTargetError.new('You must provide an :email_id and either :email_address or :subscriber_id')
      end
      
      # Get subscriber_id if it was not provided
      if subscriber_id.blank?
        subscriber = get_subscriber(email_address)
        subscriber_id = subscriber['subid']
        
        debug "Found \"#{subscriber_id}\" for #{email_address}"
        
        if subscriber_id.blank?
          raise ExactTargetError.new("Subscriber \"#{email_address}\" does not seem to exist")
        end
      end
      
      doc = ''
      xml = Builder::XmlMarkup.new(:target => doc, :indent => 1)
      
      xml.instruct!
      xml.exacttarget do |xml|
        xml.authorization do |xml|
          xml.username @user
          xml.password @password
        end
        xml.system do |xml|
          xml.system_name 'job'
          xml.action 'send_single'
          xml.search_type 'emailid'
          xml.search_value email_id
          xml.search_value2 subscriber_id
          xml.from_name options[:sender_name]
          xml.from_email options[:sender_email_address]
        end
      end
      
      response = post(doc)
      
      result = parse_send_to_subscriber_response(response.body)
      
      result
    end
    
    def get_subscriber(email_address, list_id = nil, all = false)
      doc = ''
      xml = Builder::XmlMarkup.new(:target => doc, :index => 1)
      
      xml.instruct!
      xml.exacttarget do |xml|
        xml.authorization do |xml|
          xml.username @user
          xml.password @password
        end
        xml.system do |xml|
          xml.system_name 'subscriber'
          xml.action 'retrieve'
          xml.search_type 'listid'
          xml.search_value list_id
          xml.search_value2 email_address
        end
      end
      
      response = post(doc)
      
      result = parse_get_subscriber_response(response.body)
      
      # Return the data requested.  If a list_id is passed, return that list.  If none is specified, return them all.
      if all
        result
      elsif result && (result.length > 0)
        result.find{ |r| r['list_name'] == 'All Subscribers'}
      else
        nil
      end
    end
    
    def get_subscriber_by_id(id)
    end
    
    private
    def parse_diagnostic_response(data)
      xml = REXML::Document.new(data)
      
      element = xml.elements['exacttarget/system/diagnostics/Ping']
      
      if element && (element.text == 'Running')
        true
      else
        false
      end
    end
    
    def parse_add_subscriber_response(data)
      xml = REXML::Document.new(data)
      
      element = xml.elements['exacttarget/system/subscriber/subscriber_info']
      
      if element && (element.text == 'Subscriber was added/updated successfully')
        return xml.elements['exacttarget/system/subscriber/subscriber_description'].text
      else
        false
      end
    end
    
    def parse_get_subscriber_response(data)
      xml = REXML::Document.new(data)
      
      subscribers = []
      
      xml.elements.each('/exacttarget/system/subscriber') do |subscriber|
        elements = {}
        subscriber_id = subscriber.elements.each do |element|
          elements[element.name.downcase.gsub('__','_')] = element.text
        end
        subscribers << elements
      end
      
      debug "Returning subscribers: #{subscribers.inspect}"
      
      subscribers
    end
    
    def parse_send_to_subscriber_response(data)
      xml = REXML::Document.new(data)
      
      element = xml.elements['exacttarget/system/job/job_info']
      
      if element && (element.text == 'Job was successfully created.')
        xml.elements['exacttarget/system/job/job_description'].text
      else
        false
      end
    end
    
    def parse_delete_subscriber_response(data)
      xml = REXML::Document.new(data)
      
      element = xml.elements['exacttarget/system/subscriber/subscriber_info']
      
      if element && (element.text == 'Subscriber Deleted Sucessfully')
        true
      else
        false
      end
    end
    
    def post(data)
      debug "About to post: #{data}"
      
      result = Net::HTTPS.post_form(URI.parse(API_URI), :qf => 'xml', :XML => data)
      
      debug "Received: #{result.body}"
      
      result
    end
    
    def format_attribute(attr)
      case attr
      when String
        attr.split(/[ \r\n]/).collect{ |i| i.camelize }.join('__')
      when Symbol
        attr.to_s.split(/[_\r\n]/).collect{ |i| i.camelize }.join('__')
      else
        raise
      end
    end
    
    def debug(data)
      puts data if @debug
    end
    
  end
  
end
