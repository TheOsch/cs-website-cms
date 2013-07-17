class Admin::Challenge
  include ActiveModel::Model

  STATUSES = [['Draft', 'Draft'] ,['Open for Submissions', 'Open for Submissions'] ,['Hidden', 'Hidden']]

  # Overrides the attr_accesssor class method so we are able to capture and
  # then save the defined fields as column_names
  def self.attr_accessor(*vars)
    @column_names ||= []
    @column_names.concat( vars )
    super
  end

  # Returns the previously defined attr_accessor fields
  def self.column_names
    @column_names
  end

  cattr_accessor :access_token

  attr_accessor  :id, :winner_announced, :review_date, :terms_of_service, :scorecard_type, :submission_details,
                :status, :start_date, :requirements, :name, :end_date, :description, :community_judging, :additional_info,
                :reviewers, :platforms, :technologies, :prizes, :commentNotifiers, :community, :registered_members,
                :assets, :challenge_type, :comments, :challenge_id, :submissions, :post_reg_info, :require_registration,
                :account, :contact, :auto_announce_winners, :cmc_task, :attributes, :end_time, :days_till_close, 
                :private_challenge, :page_views

  # Add validators as you like :)
  validates :name, presence: true
  validates :start_date, presence: true
  validates :end_date, presence: true
  validates :review_date, presence: true
  validates :winner_announced, presence: true
  validates :description, presence: true
  validates :requirements, presence: true
  validates :account, presence: true

  validate  do
    if start_date && end_date && winner_announced && review_date
      errors.add(:end_date, 'must be after start date') unless end_date > start_date
      errors.add(:winner_announced, 'must be after end date') unless winner_announced >= end_date.to_date
      errors.add(:review_date, 'must be after end date') unless review_date >= end_date.to_date
    end
  end

  def initialize(params={})
    # the api names some fields as challenge_xxx where as the payload needs to be xxx
    # params['reviewers'] = params.delete('challenge_reviewers') if params.include? 'challenge_reviewers'
    # params['commentNotifiers'] = params.delete('challenge_comment_notifiers') if params.include? 'challenge_comment_notifiers'
    params['prizes'] = params.delete('challenge_prizes__r') if params.include? 'challenge_prizes__r'
    params['platforms'] = params.delete('challenge_platforms__r') if params.include? 'challenge_platforms__r'
    params['technologies'] = params.delete('challenge_technologies__r') if params.include? 'challenge_technologies__r'
    params['assets'] = params.delete('assets__r') if params.include? 'assets__r'

    # just want the contact name form the contact and not their id
    if params.include? 'contact__r'
      params['contact'] = params['contact__r']['name'] unless !params['contact__r']
      params.delete('contact__r')
    end

    super(params)
  end

  def self.find(challenge_id, access_token)
    RestforceUtils.query_salesforce("select Name,Challenge_Type__c,Account__c,Contact__c,
      Require_Registration__c,Post_Reg_Info__c,Contact__r.Name,Terms_Of_Service__c,
      Scorecard_Type__c,Auto_Announce_Winners__c, additional_info__c,
      Community_Judging__c,Description__c,End_Date__c,Requirements__c,Challenge_Id__c,
      Start_Date__c,Status__c,Submission_Details__c,Winner_Announced__c,Review_Date__c, 
      (Select Place__c, Prize__c, Value__c, Points__c From Challenge_Prizes__r order by Place__c), 
      (select name__c from challenge_platforms__r order by name__c), 
      (select name__c from challenge_technologies__r order by name__c), 
      (Select Id, Filename__c From Assets__r) 
      from challenge__c where challenge_id__c = '#{challenge_id}'", access_token)
  end

  def challenge_id
    @challenge_id unless @challenge_id.blank? || nil
  end

  # Return an object instead of a string
  def start_date
    (Time.parse(@start_date) if @start_date) || Date.today
  end

  # Return an object instead of a string
  def end_date
    (Time.parse(@end_date) if @end_date) || Date.today + 7.days
  end

  # Return an object instead of a string
  def winner_announced
    (Date.parse(@winner_announced) if @winner_announced) || Date.today + 12.days
  end

  def review_date
    (Time.parse(@review_date) if @review_date) || Date.today + 9.days
  end
  
  def statuses
    Admin::Challenge::STATUSES
  end

  def scorecards
    scorecards = RestforceUtils.query_salesforce('select Name from QwikScore__c where active__c = true order by name')
    scorecards.map {|s| s.name}
  end  

  def terms_of_services
    terms = RestforceUtils.query_salesforce('select Name from Terms_of_Service__c order by name')
    terms.map {|s| s.name}
  end  

  def categories
    challenge_types = RestforceUtils.client.picklist_values('Challenge__c', 'Challenge_Type__c')
    challenge_types.map {|s| s.value}
  end    

  def communities
    # make sure we are using the correct access token
    ApiModel.access_token = access_token
    Community.all.map {|c| c.name}
  end      

  def platforms
    @platforms || []
  end

  def technologies
    @technologies || []
  end 

  def assets
    @assets || []
  end   

  def reviewers
    @reviewers || []
  end

  def commentNotifiers
    @commentNotifiers || []
  end

  def prizes
    @prizes || []
  end

  def save
    if challenge_id
      options = {
        :query => {data: payload},
        :headers => api_request_headers
      }
      Hashie::Mash.new HTTParty::put("#{ENV['CS_API_URL']}/challenges/#{challenge_id}", options)['response']    
    else
      options = {
        :body => {data: payload}.to_json,
        :headers => api_request_headers
      }
      Hashie::Mash.new HTTParty::post("#{ENV['CS_API_URL']}/challenges", options)['response']
    end
  end

  def api_request_headers
    {
      'oauth_token' => access_token,
      'Authorization' => 'Token token="'+ENV['CS_API_KEY']+'"',
      'Content-Type' => 'application/json'
    }
  end  

  # formats the object to conform to the api format
  # maybe we should use RABL for this one instead?
  def payload
    # Get the original challenge to figure out the stuff to be deleted.
    # We are re-requesting the original challenge instead of tracking which
    # entries are to be deleted client-side to minimize race conditions. Race
    # conditions aren't totally eliminated, but the window is largely smaller
    # in this case. Plus the logic is much simpler too :)

    # do not pass values that are not being fetched from sfdc. will overwrite with null

    @json_payload = {
      challenge: {
        detail: {
          account: account,
          contact: contact,
          winner_announced: winner_announced,
          terms_of_service: terms_of_service,
          scorecard_type: scorecard_type,
          submission_details: submission_details,
          status: status,
          start_date: start_date.to_time.iso8601,
          requirements: requirements,
          name: name,
          end_date: end_date.to_time.iso8601,
          description: description,
          comments: comments,
          additional_info: additional_info,
          challenge_type: challenge_type,
          community_judging: community_judging,
          auto_announce_winners: auto_announce_winners,
          community: community,
          community_judging: community_judging,
          auto_announce_winners: auto_announce_winners,
          cmc_task: cmc_task,
          challenge_id: challenge_id,
          post_reg_info: post_reg_info,
          require_registration: require_registration
        },
        reviewers: reviewers.map {|name| {name: name}}, # not being updated in sfdc
        platforms: platforms.map {|name| {name: name}},
        technologies: technologies.map {|name| {name: name}},
        prizes: prizes,
        commentNotifiers: commentNotifiers.map {|name| {name: name}}, # not being updated in sfdc
        assets: assets.map {|filename| {filename: filename}},
      }
    }
    
    remove_nil_keys # remove keys if they are nil so we don't overwrite in sfdc

    @json_payload
  end

  private

    def remove_nil_keys

      if !@json_payload[:challenge][:detail][:scorecard_type] || @json_payload[:challenge][:detail][:scorecard_type].blank?
        @json_payload[:challenge][:detail].remove_key!(:scorecard_type) 
      end

      if !@json_payload[:challenge][:detail][:terms_of_service] || @json_payload[:challenge][:detail][:terms_of_service].blank?
        @json_payload[:challenge][:detail].remove_key!(:terms_of_service)
      end

      if !@json_payload[:challenge][:detail][:cmc_task] || @json_payload[:challenge][:detail][:cmc_task].blank?
        @json_payload[:challenge][:detail].remove_key!(:cmc_task) 
      end

      if !@json_payload[:challenge][:detail][:community] || @json_payload[:challenge][:detail][:community].blank?
        @json_payload[:challenge][:detail].remove_key!(:community)
      end

    end

end