# -*- coding: utf-8 -*-
require 'json'
require 'pr_geohash'
require 'pry'

module Clustering
  DEFAULT_PRECISION = 6
  DISTANCE = 50 # Distance in pixels
  class << self
    attr_accessor :markers, :bbox, :clusters, :center_latlng, :geohash, :size
  end

  class GeoclusterHelper
    def self.distance_pixels(lat1, lng1, lat2, lng2, resolution)
      distance = self.distance_haversine(lat1, lng1, lat2, lng2)
      distance_pixels = distance / resolution * self.pixel_correction(lat1)
    end

    def self.resolutions
      r = Array.new
      max_resolution = 156.412 * 1000;
      for zoom in 1..30 do
        r[zoom] = max_resolution / (zoom * zoom)
      end
      return r
    end

    #Gives the geohash neighbors using the GeoHash.adjacent function
    def self.get_top_right_neighbors(geohash)
      neighbors = Array.new(4)
      top = GeoHash.adjacent(geohash, :top)
      neighbors[0] = GeoHash.adjacent(top, :left)
      neighbors[1] = top
      neighbors[2] = GeoHash.adjacent(top, :right)
      neighbors[3] = GeoHash.adjacent(geohash, :right)
      neighbors
    end

    private
    # PI = 3.1415926535
    RAD_PER_DEG = 0.017453293  #  PI/180
    # Rkm is earth’s radius in kilometers (mean radius = 6,371km)
    Rkm = 6371 # ...some algorithms use 6367
    # Rmeters is earth's radius in meters
    Rmeters = Rkm * 1000

    def self.pixel_correction(lat)
      1 + (335.0 / 223.271875276 - 1) * ((lat).abs / 47.9899)
    end

    #Based on http://www.codecodex.com/wiki/Calculate_Distance_Between_Two_Points_on_a_Globe#Ruby
    def self.distance_haversine(lat1, lng1, lat2, lng2)
      lat1_rad = lat1 * RAD_PER_DEG
      lng1_rad = lng1 * RAD_PER_DEG
      lat2_rad = lat2 * RAD_PER_DEG
      lng2_rad = lng2 * RAD_PER_DEG
      dlat = lat2 - lat1
      dlng = lng2 - lng2
      dlat_rad = dlat * RAD_PER_DEG
      dlng_rad = dlng * RAD_PER_DEG
      a = Math.sin(dlat_rad/2)**2 + Math.cos(lat1_rad) * Math.cos(lat2_rad) * Math.sin(dlng_rad)**2
      c = 2 * Math.sin(Math.sqrt(a))
      d = Rmeters * c
    end

  end

  class Rectangle
    attr_accessor :p1, :p2
    def initialize(p1, p2)
      if p1[0] < p2[0] and p1[1] < p2[1]
        @p1 = p1
        @p2 = p2
      else
        raise ArgumentError, "Rectangle should have points in order p1 leftmost bottom p2 rigthmost upper"
      end
    end

    def p1x
      p1[0]
    end

    def p1y
      p1[1]
    end

    def p2x
      p2[0]
    end

    def p2y
      p2[1]
    end

    def middle_point
      m = (p1x + p2x) / 2
      n = (p1y + p2y) / 2
      return [m,n]
    end

  end

  class Cluster
    attr_accessor :center_latlng, :size, :markers
    def initialize(center_latlng, markers)
      @center_latlng = center_latlng
      @markers = markers
      @size = markers.length
    end

    def to_json(*a)
      {
        :center_latlng => @center_latlng,
        :markers => @markers,
        :size => @size
      }.to_json
    end

    def x
      @center_latlng[0]
    end

    def y
      @center_latlng[1]
    end

    #Center between this cluster and other similar to the center of mass
    #between two particles
    def center_of(cluster)
      lat = 0
      lng = 0
      factor1 = self.size
      factor2 = cluster.size
      total_factor = factor1 + factor2
      lat = ((self.center_latlng[0] * factor1) + (cluster.center_latlng[0] * factor2)) / total_factor
      lng = ((self.center_latlng[1] * factor1) + (cluster.center_latlng[1] * factor2)) / total_factor
      [lat, lng]
    end

    def add_cluster(cluster)
      @markers = @markers.concat(cluster.markers)
      @size = @size + cluster.size
      @center_latlng = self.center_of(cluster)
    end

    #TODO: Check where it comes the resolution
    def should_cluster(cluster, resolution)
      lng1 = self.x
      lat1 = self.y
      lng2 = cluster.x
      lat2 = cluster.y
      distance = GeoclusterHelper.distance_pixels(lat1, lng1, lat2, lng2, resolution)
      (distance < DISTANCE)
    end

    def generate_geohash()
      geohash = GeoHash.encode(@center_latlng[0], @center_latlng[1])
    end

  end

  def self.init(markers, padding=0.001, precision=DEFAULT_PRECISION)
    mks = JSON.parse(markers)
    mks = mks['markers']
    @clusters = Hash.new
    @size = mks.size
    lat_a = (mks.values.map { |m| m["lat"] }).sort
    lng_a = (mks.values.map { |m| m["lng"] }).sort
    #returns bounding box [x1,y1,x2,y2]
    p1 = [lng_a.first - padding, lat_a.first - padding]
    p2 = [lng_a.last + padding, lat_a.last + padding]
    @bbox = Rectangle.new(p1,p2)

    #Returns a Rectangle that represents the bounding box for all the coordinates
    puts "Initial bbox: #{@bbox.p1x},#{@bbox.p1y}, #{@bbox.p2x}, #{@bbox.p2y}"
    puts "Size: #{@size}"
    #binding.pry

    counter = 0
    #Initializing geohashes
    mks.each { |key, val|
      geohash = GeoHash.encode(val["lat"], val["lng"])
      val["geohash"] = geohash
      hash_key = geohash[0...precision]
      if(@clusters[hash_key])
        #puts "Original size: #{@clusters[hash_key].size}"
        #We create a new cluster using lat,lng coordinates and the marker values
        simple_cluster = Cluster.new([val["lat"], val["lng"]], [val])
        #we merged with the existing cluster
        @clusters[hash_key].add_cluster(simple_cluster)
        #puts @clusters[hash_key].size
      else
        @clusters[hash_key] = Cluster.new([val["lat"], val["lng"]], [val])
        #puts @clusters[hash_key].size
      end
    }
    p,s =  @bbox.middle_point
    @center_latlng = [p,s]
  end

  #private

  def self.cluster_by_neighbor_check(resolution)
    #We sort the cluster by key (that means by geohash)
    sorted = @clusters.sort
    #For each geohash...
    sorted.each{ |val|
      #Current geohash
      current_key = val[0]
      #Current cluster
      current = val[1]
      #Checking if we haven't merged it
      if (@clusters[current_key] == nil )
        next
      end
      neighbors = GeoclusterHelper.get_top_right_neighbors(current_key)
      neighbors.each{ |n|
        if @clusters[n] != nil
          neighbor = @clusters[n]
          if (current.should_cluster(neighbor, resolution))
            puts "#{@clusters[n]} key #{n} is a neighbor of #{current_key}, #{current}"
            puts "And should been merged... merging"
            @clusters[current_key].add_cluster(neighbor)
            @clusters[n] = nil
          end
        end
      }
      #Here the key of the current key should be change according to the new center
      geohash = @clusters[current_key].generate_geohash()
      @clusters[geohash] = @clusters[current_key]
      @clusters[current_key] = nil
    }
    @clusters = @clusters.delete_if { |k, v| v.nil? }
    #binding.pry
  end

  def self.geohash_clustering_algorithm(markers, zoom = 8, distance = DISTANCE)
    #self.init(markers);
    resolutions = GeoclusterHelper.resolutions()
    resolution = resolutions[zoom]
    self.cluster_by_neighbor_check(resolution)
  end

end
