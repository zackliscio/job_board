require 'will_paginate/array'

class UsersController < ApplicationController
  # rescue_from ActiveRecord::Errors, :with => :has_same_name

  # before_filter :check_for_cancel, only: [:edit, :update]
  before_filter :signed_in_user, except: [:index, :show, :category]
  before_filter :catch_cancel, update: [:create, :update, :destroy]
  after_filter :set_referrer, only: [:index, :show]
  before_filter :find_user, only: [:show, :edit, :update, :plus, :minus]
  before_filter :correct_user, only: [:edit, :update]
  before_filter :set_pref, only: [:show, :edit]
  before_filter :format_job_pref, only: [:create, :update]
  before_filter :search

  def index
    logger.debug 'inside INDEX'
  	@users_by_job_pref = Hash.new
    CATEGORY.each_with_index do |choice, index|
      result = User.in_job_preference(index.to_s).sort{ |r2, r1| # this sorts in ASC order
        ((r1.job_pref_pnts.nil?) ? "" : r1.job_pref_pnts.split(","))[index].to_i <=> 
        ((r2.job_pref_pnts.nil?) ? "" : r2.job_pref_pnts.split(","))[index].to_i 
      }

      if(!result.blank?)
        @users_by_job_pref[choice] = result
      end
    end
    @users_no_job_pref = User.no_job_pref
    
    respond_to do |format|
      format.html
      format.json { render json: @users_by_job_pref }
    end
  end

  def show
    @games = @user.games
    @recorded_points = (@user.job_pref_pnts.nil?) ? "" : @user.job_pref_pnts.split(',')
    @all_games = Game.all(order: "id ASC")
    @user_extra = @user.extra
  end

	def edit
    logger.debug 'inside EDIT'

		if @user.new_user?
      @user.update_attribute(:new_user, "false")
		end
	end

	def update
    logger.debug 'inside UPDATE'
		params[:user][:new_user] = 'false'

		if @user.update_attributes(params[:user])
			flash[:success] = "Profile update successful!"
			redirect_to edit_user_path(@user)
		else
      render 'edit'
		end
	end

  def vote
    # get/set values
    logger.debug params
    user_voted = params[:id].to_i # user id for voted user
    job_preference = params[:jobpref]
    voters = Array.new

    if current_user.id != user_voted
      vote_record = Vote.jobpref_vote(job_preference, user_voted)

      if !vote_record.blank?
        vote_record.each do |vote|
          voters.push(vote.user_id)
        end

        if !voters.include?(current_user.id)
          cast_vote(job_preference, user_voted)
        else
          Vote.where(user_id: current_user.id, job_preference: job_preference, user_voted: user_voted).delete_all
          vote_details = Vote.jobpref_vote(job_preference, user_voted)
          # redirect_to :back, flash: { success: "Vote subtracted." }    
          render json: { success: "Vote subtracted.", votes: vote_details.count }, status: 200
        end
      else
        cast_vote(job_preference, user_voted)
      end
    else
      vote_details = Vote.jobpref_vote(job_preference, user_voted)
      # redirect_to :back, flash: { error: "You are not allowed to vote for yourself." }
      render json: { errors: "You are not allowed to vote for yourself.", votes: vote_details.count }, status: 422
    end
  end

  def plus
    job_preference = params[:jobpref].to_i
    recorded_points = (@user.job_pref_pnts.nil?) ? "" : @user.job_pref_pnts.split(',')
    remaining_pnts = @user.remaining_pnts
    points = Array.new
    pnt = 0

    CATEGORY.each_with_index do |choice, index|
      if job_preference == index
        num = (recorded_points.empty?) ? 0 : recorded_points[index].to_i
        pnt = num + 1
        if(remaining_pnts > 0)
          points.push((pnt).to_s)
          remaining_pnts -= 1
        else
          points.push("0")
          # redirect_to :back, flash: { error: "Cannot set value greater than your points: #{remaining_pnts}." } and return
          render json: { errors: "Cannot set value greater than your remaining points." }, status: 422 and return
        end
      else
        if recorded_points.empty?
          points.push("0")
        else
          points.push(recorded_points[index])
        end
      end
    end

    if @user.update_attributes({"job_pref_pnts" => points.join(','), "remaining_pnts" => remaining_pnts})
      # redirect_to :back and return
      render json: { success: "Point added.", points: pnt, remaining: remaining_pnts }, status: 200 and return
    else
      render 'edit'
    end
    # redirect_to :back, flash: { success: "Plus! #{points.join(',')}" }
  end

  def minus
    job_preference = params[:jobpref].to_i
    recorded_points = (@user.job_pref_pnts.nil?) ? "" : @user.job_pref_pnts.split(',')
    remaining_pnts = @user.remaining_pnts
    points = Array.new
    pnt = 0

    CATEGORY.each_with_index do |choice, index|
      if job_preference == index
        num = (recorded_points.empty?) ? 0 : recorded_points[index].to_i
        pnt = num - 1
        if(pnt > -1)
          points.push((pnt).to_s)
          remaining_pnts += 1
        else
          points.push("0")
          # redirect_to :back, flash: { error: "Cannot set value lesser than 0." } and return
          render json: { errors: "Cannot set value lesser than 0." }, status: 422 and return
        end
      else
        if recorded_points.empty?
          points.push("0")
        else
          points.push(recorded_points[index])
        end
      end
    end

    if @user.update_attributes({"job_pref_pnts" => points.join(','), "remaining_pnts" => remaining_pnts})
      # redirect_to :back and return
      render json: { success: "Point subtracted.", points: pnt, remaining: remaining_pnts }, status: 200 and return
    else
      render 'edit'
    end
    # redirect_to :back, flash: { success: "Minus! #{points.join(',')}" }
  end


  def category
    logger.debug 'inside category'
    @cat_id = CATEGORY.index(params[:name])
    @users = User.in_job_preference(@cat_id.to_s).sort{ |r2, r1| # this sorts in ASC order
      ((r1.job_pref_pnts.nil?) ? "" : r1.job_pref_pnts.split(","))[@cat_id].to_i <=> 
      ((r2.job_pref_pnts.nil?) ? "" : r2.job_pref_pnts.split(","))[@cat_id].to_i 
    }
    if @users.size == 0
      render 'static_pages/user_error'
    else
      @users = @users.paginate(page: params[:page], per_page: NUMBER_LIMIT)
      
      @users.each do |user|
        classname = "up-btn"
        vote_details = Vote.jobpref_vote(@cat_id, user.id)
        if !vote_details.blank? && current_user.nil? # not signed-in
          classname = "red-btn"
        end 

        if !current_user.nil? && vote_details.any? {|u| u.user_id == current_user.id} # signed-in and voted
          classname = "red-btn"
        end

        logger.debug vote_details.length.to_s + classname
        user[:vote_count] = vote_details.length
        user[:vote_color] = classname
      end
    end

    respond_to do |format| #not used when there is .js.erb file
      format.json {
        render json: {
          current_page: @users.current_page,
          per_page: @users.per_page,
          total_entries: @users.total_entries,
          entries: @users.as_json(include: {games: {only: [:name] }}, methods: [:vote_count, :vote_color])
        }, status: 200
      }
      format.html
    end
  end

  # def user_game
  #   games = User.find(params[:userid]).games

  #   logger.debug games
  #   counter = 0 
  #   game_list = Array.new
  #   if !games.blank? 
  #     games.each do |game| 
  #       if counter < 3 
  #         game_list.push(game.name)
  #         counter += 1
  #       end 
  #     end
  #     game_list.join(",")     
  #     # render json: { errors: "Unable to search user games." }, status: 422 and return
  #   end
  #     render json: { success: "User games found.", games: game_list}, status: 200 and return
  # end

  # def user_vote
  #   get_vote_details(thisuser_id, jobpref, user.id) # call votes_helper method that creates @vote_details
  #   classname = "up-btn"
  #   if !@vote_details.blank? && current_user.nil? # not signed-in
  #     classname = "red-btn"
  #   end 

  #   if !current_user.nil? && @vote_details.any? {|u| u.user_id == current_user.id} # signed-in and voted
  #     classname = "red-btn"
  #   end 

  #   if current_user 

  #   end
  # end

	private

    def signed_in_user
      logger.debug "inside signed_in_user"
      logger.debug signed_in?

      redirect_to root_url, flash: { error: "Action not allowed because you are not signed in." } unless signed_in?
    end

    def correct_user
      logger.debug "inside correct_user"
      if @user.id != current_user.id
        redirect_to root_url, flash: { error: "Action not allowed because you are attempting to update another user's info." }
      end
    end

    def find_user
      @user = User.find(params[:id])
    end

    def set_pref
      @job_preference = (@user.job_preference.nil?) ? "" : @user.job_preference.split(',')
      @job_pref_pnts = (@user.job_pref_pnts.nil?) ? "" : @user.job_pref_pnts.split(',')
    end

    def set_referrer
      session[:referrer] = url_for(params)
      # session[:referrer] = request.referer
    end

    def catch_cancel
      redirect_to session[:referrer] if params[:commit] == "Cancel"
    end
    
    def has_same_name 
      flash[:error] = "User has been registered."
      redirect_to :root
    end

    def check_for_cancel
    logger.debug 'inside check_for_cancel'
      if params[:commit] == "Cancel" || params[:commit] == "OK"
        redirect_to jobs_path
      end
    end

    # gets the value of params[:lecture][:job_preference] and builds an array from it
    def format_job_pref
      logger.debug "inside format_job_pref"
      logger.debug "params: " + params.to_s

      if(!params[:user][:job_preference].nil?)
        @job_preference = params[:user][:job_preference].join(',')
      else
        @job_preference = ''
      end
      
      params[:user][:job_preference] = @job_preference
    end

    def cast_vote(job_preference, user_voted)
      # cast new vote
      vote = current_user.votes.new(job_preference: job_preference, user_voted: user_voted)
      if vote.save
        vote_details = Vote.jobpref_vote(job_preference, user_voted)
        # redirect_to :back, flash: { success: "Vote counted." }      
        render json: { success: "Vote counted.", votes: vote_details.count }, status: 200
      else
        vote_details = Vote.jobpref_vote(job_preference, user_voted)
        # redirect_to :back, flash: { error: "Unable to vote, perhaps you already did." }        
        render json: { errors: "Unable to vote, perhaps you already did.", votes: vote_details.count }, status: 422
      end
    end

    def search
      @word = word = params[:search]
      @availability = availability = @location = nil

      @user_search = 0
      if !@word.nil? || !@availability.nil? || !@location.nil?
        if @word != "" || !@word.blank?
          @grouped_user_results = Hash.new
          CATEGORY.each_with_index do |choice, index|
            if((choice.downcase).include?(@word))
              word = index.to_s
            end
          end
        end

        @availability = availability = params[:availability]
        @location = params[:location]

        if @availability != "" || !@availability.blank?
          AVAILABILITY.each_with_index do |choice, index|
            if((choice.downcase).include?(@availability.downcase))
              availability = index
            end
          end
        else
          availability = -1
        end

        @user_results = User.search(word, availability, @location)
        if(!@user_results.blank?)
          @grouped_user_results = @user_results
        end

        @user_search = @user_results.length
        render 'search'
      end
    end
end
