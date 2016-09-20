//
//  GooglePlacesAutocomplete.swift
//  GooglePlacesAutocomplete
//
//  Created by Howard Wilson on 10/02/2015.
//  Copyright (c) 2015 Howard Wilson. All rights reserved.
//

import UIKit

public enum PlaceType: CustomStringConvertible {
    case all
    case geocode
    case address
    case establishment
    case regions
    case cities
    
    public var description : String {
        switch self {
        case .all: return ""
        case .geocode: return "geocode"
        case .address: return "address"
        case .establishment: return "establishment"
        case .regions: return "(regions)"
        case .cities: return "(cities)"
        }
    }
}

open class Place: NSObject {
    open let id: String
    open let desc: String
    open var apiKey: String?
    
    override open var description: String {
        get { return desc }
    }
    
    public init(id: String, description: String) {
        self.id = id
        self.desc = description
    }
    
    public convenience init(prediction: [String: AnyObject], apiKey: String?) {
        self.init(
            id: prediction["place_id"] as! String,
            description: prediction["description"] as! String
        )
        
        self.apiKey = apiKey
    }
    
    /**
     Call Google Place Details API to get detailed information for this place
     
     Requires that Place#apiKey be set
     
     :param: result Callback on successful completion with detailed place information
     */
    open func getDetails(_ result: @escaping (PlaceDetails) -> ()) {
        GooglePlaceDetailsRequest(place: self).request(result)
    }
}

open class PlaceDetails: CustomStringConvertible {
    open let name: String
    open let latitude: Double
    open let longitude: Double
    open let raw: [String: AnyObject]
    
    public init(json: [String: AnyObject]) {
        let result = json["result"] as! [String: AnyObject]
        let geometry = result["geometry"] as! [String: AnyObject]
        let location = geometry["location"] as! [String: AnyObject]
        
        self.name = result["name"] as! String
        self.latitude = location["lat"] as! Double
        self.longitude = location["lng"] as! Double
        self.raw = json
    }
    
    open var description: String {
        return "PlaceDetails: \(name) (\(latitude), \(longitude))"
    }
}

@objc public protocol GooglePlacesAutocompleteDelegate {
    @objc optional func placesFound(_ places: [Place])
    @objc optional func placeSelected(_ place: Place)
    @objc optional func placeViewClosed()
    @objc optional func placeViewClosedCanceled()
}

// MARK: - GooglePlacesAutocomplete
open class GooglePlacesAutocomplete: UINavigationController {
    open var gpaViewController: GooglePlacesAutocompleteContainer!
    open var closeButton: UIBarButtonItem!
    
    // Proxy access to container navigationItem
    open override var navigationItem: UINavigationItem {
        get { return gpaViewController.navigationItem }
    }
    
    open var placeDelegate: GooglePlacesAutocompleteDelegate? {
        get { return gpaViewController.delegate }
        set { gpaViewController.delegate = newValue }
    }
    
    public convenience init(apiKey: String, placeType: PlaceType = .all) {
        let gpaViewController = GooglePlacesAutocompleteContainer(
            apiKey: apiKey,
            placeType: placeType
        )
        
        self.init(rootViewController: gpaViewController)
        self.gpaViewController = gpaViewController
        
        closeButton = UIBarButtonItem(barButtonSystemItem: UIBarButtonSystemItem.stop, target: self, action: #selector(GooglePlacesAutocomplete.closeCanceled))
        closeButton.style = UIBarButtonItemStyle.done
        
        gpaViewController.navigationItem.leftBarButtonItem = closeButton
        gpaViewController.navigationItem.title = "Enter Address"
    }
    
    func close() {
        placeDelegate?.placeViewClosed?()
    }
    
    func closeCanceled() {
        placeDelegate?.placeViewClosedCanceled?()
    }
    
    open func reset() {
        gpaViewController.searchBar.text = ""
        gpaViewController.searchBar(gpaViewController.searchBar, textDidChange: "")
    }
}

// MARK: - GooglePlacesAutocompleteContainer
open class GooglePlacesAutocompleteContainer: UIViewController {
    @IBOutlet open weak var searchBar: UISearchBar!
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var topConstraint: NSLayoutConstraint!
    
    var delegate: GooglePlacesAutocompleteDelegate?
    var apiKey: String?
    var places = [Place]()
    var placeType: PlaceType = .all
    
    convenience init(apiKey: String, placeType: PlaceType = .all) {
        let bundle = Bundle(for: GooglePlacesAutocompleteContainer.self)
        
        self.init(nibName: "GooglePlacesAutocomplete", bundle: bundle)
        self.apiKey = apiKey
        self.placeType = placeType
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override open func viewWillLayoutSubviews() {
        topConstraint.constant = topLayoutGuide.length
    }
    
    override open func viewDidLoad() {
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(self, selector: #selector(GooglePlacesAutocompleteContainer.keyboardWasShown(_:)), name: NSNotification.Name.UIKeyboardDidShow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(GooglePlacesAutocompleteContainer.keyboardWillBeHidden(_:)), name: NSNotification.Name.UIKeyboardWillHide, object: nil)
        
        searchBar.becomeFirstResponder()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
    }
    
    func keyboardWasShown(_ notification: Notification) {
        if isViewLoaded && view.window != nil {
            let info: Dictionary = (notification as NSNotification).userInfo!
            let keyboardSize: CGSize = ((info[UIKeyboardFrameBeginUserInfoKey] as AnyObject).cgRectValue.size)
            let contentInsets = UIEdgeInsetsMake(0.0, 0.0, keyboardSize.height, 0.0)
            
            tableView.contentInset = contentInsets;
            tableView.scrollIndicatorInsets = contentInsets;
        }
    }
    
    func keyboardWillBeHidden(_ notification: Notification) {
        if isViewLoaded && view.window != nil {
            self.tableView.contentInset = UIEdgeInsets.zero
            self.tableView.scrollIndicatorInsets = UIEdgeInsets.zero
        }
    }
}

// MARK: - GooglePlacesAutocompleteContainer (UITableViewDataSource / UITableViewDelegate)
extension GooglePlacesAutocompleteContainer: UITableViewDataSource, UITableViewDelegate {
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return places.count
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) 
        
        // Get the corresponding candy from our candies array
        let place = self.places[(indexPath as NSIndexPath).row]
        
        // Configure the cell
        cell.textLabel!.text = place.description
        cell.accessoryType = UITableViewCellAccessoryType.disclosureIndicator
        
        return cell
    }
    
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        delegate?.placeSelected?(self.places[(indexPath as NSIndexPath).row])
    }
}

// MARK: - GooglePlacesAutocompleteContainer (UISearchBarDelegate)
extension GooglePlacesAutocompleteContainer: UISearchBarDelegate {
    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if (searchText == "") {
            self.places = []
            tableView.isHidden = true
        } else {
            //print (searchText+" this search text though")
            getPlaces(searchText)
        }
    }
    
    /**
     Call the Google Places API and update the view with results.
     
     :param: searchString The search query
     */
    fileprivate func getPlaces(_ searchString: String) {
        //the call below is not returning the api and what not
        //print (placeType.description, "this desc")
        
        GooglePlacesRequestHelpers.doRequest(
            "https://maps.googleapis.com/maps/api/place/autocomplete/json",
            params: [
                "input": searchString,
                "types": "establishment",//placeType.description
                "key": apiKey ?? ""
            ]
            ) { json in
                if let predictions = json["predictions"] as? Array<[String: AnyObject]> {
                    self.places = predictions.map { (prediction: [String: AnyObject]) -> Place in
                        return Place(prediction: prediction, apiKey: self.apiKey)
                    }
                    
                    /*
                    for place in self.places {
                    print("found a place")
                    print(place)
                    }
                    */
                    
                    self.tableView.reloadData()
                    self.tableView.isHidden = false
                    self.delegate?.placesFound?(self.places)
                }
        }
    }
}

// MARK: - GooglePlaceDetailsRequest
class GooglePlaceDetailsRequest {
    let place: Place
    
    init(place: Place) {
        self.place = place
    }
    
    func request(_ result: @escaping (PlaceDetails) -> ()) {
        GooglePlacesRequestHelpers.doRequest(
            "https://maps.googleapis.com/maps/api/place/details/json",
            params: [
                "placeid": place.id,
                "key": place.apiKey ?? ""
            ]
            ) { json in
                result(PlaceDetails(json: json as! [String: AnyObject]))
        }
    }
}

// MARK: - GooglePlacesRequestHelpers
class GooglePlacesRequestHelpers {
    /**
     Build a query string from a dictionary
     
     :param: parameters Dictionary of query string parameters
     :returns: The properly escaped query string
     */
    fileprivate class func query(_ parameters: [String: AnyObject]) -> String {
        var toReturn = ""
        var components: [(String, String)] = []
        for key in (Array(parameters.keys).sorted()) {
            let value: AnyObject! = parameters[key]
            //print (key)
            //print (value)
            
            /* this code isnt working, sorresponds to line 309. Supposed to do same as 300 */
            components += [(escape(key), escape("\(value)"))]
            
            toReturn += key+"="+(value as! String)+"&"
        }
        
        //join("&", components.map{"\($0)=\($1)"} as [String])
        
        return toReturn
    }
    
    fileprivate class func escape(_ string: String) -> String {
        let legalURLCharactersToBeEscaped: CFString = ":/?&=;+!@#$()',*" as CFString
        return CFURLCreateStringByAddingPercentEscapes(nil, string as CFString!, nil, legalURLCharactersToBeEscaped, CFStringBuiltInEncodings.UTF8.rawValue) as String
    }
    
    class func doRequest(_ url: String, params: [String: String], success: @escaping (NSDictionary) -> ()) {
        var params = params
        if (params.count == 3) {
            params["input"]! = params["input"]!.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)!
            /*if (params["input"]!.rangeOfString(" ") != nil) {
              params["input"] = params["input"]!.stringByReplacingOccurrencesOfString(" ", withString: "%20")
            }*/
        }
        let request = URLRequest(
            url: URL(string: "\(url)?\(query(params as [String : AnyObject]))")!
        )
        
        let session = URLSession.shared
        let task = session.dataTask(with: request) {
          (data:Data?, response:URLResponse?, error:Error?) in
            self.handleResponse(data, response: response as! HTTPURLResponse!, error: error as NSError!, success: success)
        }
        
        task.resume()
    }
    
    fileprivate class func handleResponse(_ data: Data!, response: HTTPURLResponse!, error: NSError!, success: @escaping (NSDictionary) -> ()) {
        if let error = error {
            print("GooglePlaces Error: \(error.localizedDescription)")
            return
        }
        
        if response == nil {
            print("GooglePlaces Error: No response from API")
            return
        }
        
        if response.statusCode != 200 {
            print("GooglePlaces Error: Invalid status code \(response.statusCode) from API")
            return
        }
        
        let serializationError: NSError? = nil
        do {
            let json: NSDictionary = try JSONSerialization.jsonObject(
                with: data,
                options: JSONSerialization.ReadingOptions.mutableContainers
                //error: &serializationError
                ) as! NSDictionary
            
            DispatchQueue.main.async(execute: {
                UIApplication.shared.isNetworkActivityIndicatorVisible = false
                
                success(json)
            })
        } catch {
            print(error)
            
        }
        
        if let error = serializationError {
            print("GooglePlaces Error: \(error.localizedDescription)")
            return
        }
        /*
        if let status = json["status"] as? String {
        if status != "OK" {
        print("GooglePlaces API Error: \(status)")
        return
        }
        }
        
        // Perform table updates on UI thread
        dispatch_async(dispatch_get_main_queue(), {
        UIApplication.sharedApplication().networkActivityIndicatorVisible = false
        
        success(json)
        })
        */
    }
}
