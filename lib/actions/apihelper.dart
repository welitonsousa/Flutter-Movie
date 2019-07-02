import 'dart:convert' show json;
import 'dart:ui' as ui;
import 'dart:io';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:movie/models/accountdetail.dart';
import 'package:movie/models/certification.dart';
import 'package:movie/models/combinedcredits.dart';
import 'package:movie/models/creditsmodel.dart';
import 'package:movie/models/imagemodel.dart';
import 'package:movie/models/keyword.dart';
import 'package:movie/models/moviechange.dart';
import 'package:movie/models/moviedetail.dart';
import 'package:movie/models/peopledetail.dart';
import 'package:movie/models/videolist.dart';
import 'package:movie/models/review.dart';
import 'package:movie/models/searchresult.dart';
import 'package:movie/models/tvdetail.dart';
import 'package:movie/models/videomodel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiHelper {
  static final String _apihost = 'https://api.themoviedb.org/3';
  static final String _apikey = 'd7ff494718186ed94ee75cf73c1a3214';
  static final String _apikeyV4 =
      'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJhdWQiOiJkN2ZmNDk0NzE4MTg2ZWQ5NGVlNzVjZjczYzFhMzIxNCIsInN1YiI6IjVkMDQ1OWM1OTI1MTQxNjNkMWJjNDZjYiIsInNjb3BlcyI6WyJhcGlfcmVhZCJdLCJ2ZXJzaW9uIjoxfQ.tTDwJEVH88cCWCfTd42zvN4AsMR2pgix0QdzVJQzzDM';
  static String _requestToken;
  static DateTime _requestTokenExpiresTime;
  static String session;
  static DateTime _sessionExpiresTime;
  static SharedPreferences prefs;
  static String _appDocPath;
  static CookieJar _cj;
  static String language = ui.window.locale.languageCode;
  static String region = ui.window.locale.countryCode;

  static Future<void> getCookieDir() async {
    prefs = await SharedPreferences.getInstance();
    Directory appDocDir = await getApplicationDocumentsDirectory();
    _appDocPath = appDocDir.path;
    _cj = new PersistCookieJar(dir: "$_appDocPath/cookies");
  }

  static Future createGuestSession() async {
    String param = '/authentication/guest_session/new?api_key=$_apikey';
    var r = await httpGet(param);
    if (r != null) {
      var jsonobject = json.decode(r);
      if (jsonobject['success']) {
        session = jsonobject['guest_session_id'];
        _sessionExpiresTime = DateTime.parse(jsonobject['expires_at']
            .toString()
            .replaceFirst(new RegExp(' UTC'), ''));
      }
    }
  }

  static Future createRequestToken() async {
    String param = '/authentication/token/new?api_key=$_apikey';
    var r = await httpGet(param);
    if (r != null) {
      var jsonobject = json.decode(r);
      if (jsonobject['success']) {
        _requestToken = jsonobject['request_token'];
        _requestTokenExpiresTime = DateTime.parse(jsonobject['expires_at']
            .toString()
            .replaceFirst(new RegExp(' UTC'), ''));
      }
    }
  }

  static Future createSessionWithLogin(String account, String pwd) async {
    if (_requestToken == null) await createRequestToken();
    String param = '/authentication/token/validate_with_login';
    FormData formData = new FormData.from(
        {"username": account, "password": pwd, "request_token": _requestToken});
    var r = await httpPost(param, formData);
    if (r != null) {
      var jsonobject = json.decode(r);
      if (jsonobject['success']) {
        await createNewSession(_requestToken);
      }
    }
  }

  static Future createNewSession(String sessionToken) async {
    if (session != null) {
      String param = '/authentication/session/new';
      FormData formData = new FormData.from({"request_token": sessionToken});
      var r = await httpPost(param, formData);
      if (r != null) {
        var jsonobject = json.decode(r);
        if (jsonobject['success']) {
          session = jsonobject['session_id'];
          prefs.setString('loginsession', session);
          await getAccountDetail();
        }
      }
    }
  }

  static Future createSessionWithV4(String sessionToken) async {
    String param = '/authentication/session/convert/4';
    FormData formData = new FormData.from({"access_token": _apikeyV4});
    var r = await httpPost(param, formData);
    if (r != null) {
      var jsonobject = json.decode(r);
      if (jsonobject['success']) {
        session = jsonobject['session_id'];
        _sessionExpiresTime = DateTime.parse(jsonobject['expires_at']
            .toString()
            .replaceFirst(new RegExp(' UTC'), ''));
        prefs.setString('loginsession', session);
        prefs.setString(
            'loginsessionexpires', _sessionExpiresTime.toIso8601String());
      }
    }
  }

  static Future<AccountDetailModel> getAccountDetail() async {
    AccountDetailModel accountDetailModel;
    if (session != null) {
      String param = '/account?api_key=$_apikey&session_id=$session';
      var r = await httpGet(param);
      if (r != null) accountDetailModel = AccountDetailModel(r);
      prefs.setInt('accountid', accountDetailModel.id);
      prefs.setBool('islogin', true);
      prefs.setString('accountname', accountDetailModel.username);
      prefs.setString('accountgravatar',
          'https://www.gravatar.com/avatar/${accountDetailModel.avatar.gravatar.hash}?size=200');
    }
    return accountDetailModel;
  }

  static Future<bool> deleteSession() async {
    String param = '/authentication/session';
    if (session != null) {
      FormData formData = new FormData.from({"session_id": session});
      var r = await httpDelete(param, formData);
      if (r != null) {
        var jsonobject = json.decode(r);
        if (jsonobject['success']) {
          prefs.remove('loginsession');
          prefs.remove('accountid');
          prefs.remove('accountname');
          prefs.remove('accountgravatar');
          prefs.remove('islogin');
        } else
          return false;
      }
    }
    return true;
  }

  ///Get a list of all the movies you have rated.
  static Future<VideoListModel> getRatedMovies({int page = 1}) async {
    int accountid = prefs.getInt('accountid');
    if (accountid == null) return null;
    VideoListModel model;
    String param =
        '/account/$accountid/rated/movies?api_key=$_apikey&language=$language&session_id=$session&sort_by=created_at.asc&page=$page';
    var r = await httpGet(param);
    if (r != null) model = VideoListModel(r);
    return model;
  }

  ///Get a list of all the movies you have rated.
  static Future<VideoListModel> getRatedTVShows({int page = 1}) async {
    int accountid = prefs.getInt('accountid');
    if (accountid == null) return null;
    VideoListModel model;
    String param =
        '/account/$accountid/rated/tv?api_key=$_apikey&language=$language&session_id=$session&sort_by=created_at.asc&page=$page';
    var r = await httpGet(param);
    if (r != null) model = VideoListModel(r);
    return model;
  }

  static Future<CertificationModel> getMovieCertifications() async {
    CertificationModel certificationModel;
    String param = '/certification/movie/list';
    var r = await httpGet(param);
    if (r != null) {
      certificationModel = CertificationModel(r);
    }
    return certificationModel;
  }

  static Future<CertificationModel> getTVCertifications() async {
    CertificationModel certificationModel;
    String param = '/certification/tv/list';
    var r = await httpGet(param);
    if (r != null) {
      certificationModel = CertificationModel(r);
    }
    return certificationModel;
  }

  static Future<VideoListModel> getPopularMovies({int page = 1}) async {
    VideoListModel model;
    String param =
        "/movie/popular?api_key=$_apikey&language=$language&page=$page";
    var r = await httpGet(param);
    if (r != null) model = VideoListModel(r);
    return model;
  }

  static Future<VideoListModel> getPopularTVShows({int page = 1}) async {
    VideoListModel model;
    String param = "/tv/popular?api_key=$_apikey&language=$language&page=$page";
    var r = await httpGet(param);
    if (r != null) model = VideoListModel(r);
    return model;
  }

  static Future<MovieDetailModel> getMovieDetail(int mvid,
      {String appendtoresponse}) async {
    MovieDetailModel model;
    String param = '/movie/$mvid?api_key=$_apikey&language=$language';
    if (appendtoresponse != null)
      param = param + '&append_to_response=$appendtoresponse';
    var r = await httpGet(param);
    if (r != null) model = MovieDetailModel(r);
    return model;
  }

  static Future<TVDetailModel> getTVDetail(int mvid,
      {String appendtoresponse}) async {
    TVDetailModel model;
    String param = '/tv/$mvid?api_key=$_apikey&language=$language';
    if (appendtoresponse != null)
      param = param + 'append_to_response=$appendtoresponse';
    var r = await httpGet(param);
    if (r != null) model = TVDetailModel(r);
    return model;
  }

  ///Get a list of all of the movie ids that have been changed in the past 24 hours.You can query it for up to 14 days worth of changed IDs at a time with the start_date and end_date query parameters. 100 items are returned per page.
  static Future<MovieChangeModel> getMovieChange(
      {int page = 1, String startdate, String enddate}) async {
    MovieChangeModel model;
    String param = '/movie/changes?api_key=$_apikey&page=$page';
    if (startdate != null && enddate == null)
      param = param + '&start_date=$enddate&start_date=$startdate';
    var r = await httpGet(param);
    if (r != null) model = MovieChangeModel(r);
    return model;
  }

  ///Get a list of upcoming movies in theatres. This is a release type query that looks for all movies that have a release type of 2 or 3 within the specified date range.You can optionally specify a region prameter which will narrow the search to only look for theatrical release dates within the specified country.
  static Future<VideoListModel> getMoviceUpComing({int page = 1}) async {
    VideoListModel model;
    String param =
        '/movie/upcoming?api_key=$_apikey&language=$language&page=$page&region=$region';
    var r = await httpGet(param);
    if (r != null) model = VideoListModel(r);
    return model;
  }

  ///Get a list of movies in theatres. This is a release type query that looks for all movies that have a release type of 2 or 3 within the specified date range.You can optionally specify a region prameter which will narrow the search to only look for theatrical release dates within the specified country.
  static Future<VideoListModel> getNowPlayingMovie({int page = 1}) async {
    VideoListModel model;
    String param =
        '/movie/now_playing?api_key=$_apikey&language=$language&page=$page&region=$region';
    var r = await httpGet(param);
    if (r != null) model = VideoListModel(r);
    return model;
  }

  static Future<VideoListModel> getRecommendationsMovie(int movieid,
      {int page = 1}) async {
    VideoListModel model;
    String param =
        '/movie/$movieid/recommendations?api_key=$_apikey&language=$language&page=$page';
    var r = await httpGet(param);
    if (r != null) model = VideoListModel(r);
    return model;
  }

  static Future<VideoListModel> getRecommendationsTV(int tvid,
      {int page = 1}) async {
    VideoListModel model;
    String param =
        '/tv/$tvid/recommendations?api_key=$_apikey&language=$language&page=$page';
    var r = await httpGet(param);
    if (r != null) model = VideoListModel(r);
    return model;
  }

  ///Get the videos that have been added to a movie.
  static Future<VideoModel> getMovieVideo(int movieid) async {
    VideoModel model;
    String param = '/movie/$movieid/videos?api_key=$_apikey';
    var r = await httpGet(param);
    if (r != null) model = VideoModel(r);
    return model;
  }

  static Future<VideoModel> getTVVideo(int tvid) async {
    VideoModel model;
    String param = '/tv/$tvid/videos?api_key=$_apikey';
    var r = await httpGet(param);
    if (r != null) model = VideoModel(r);
    return model;
  }

  ///Get a list of shows that are currently on the air.This query looks for any TV show that has an episode with an air date in the next 7 days.
  static Future<VideoListModel> getTVOnTheAir({int page = 1}) async {
    VideoListModel model;
    String param =
        '/tv/on_the_air?api_key=$_apikey&language=$language&page=$page';
    var r = await httpGet(param);
    if (r != null) model = VideoListModel(r);
    return model;
  }

  ///Search multiple models in a single request. Multi search currently supports searching for movies, tv shows and people in a single request.
  static Future<SearchResultModel> searchMulit(
      {int page = 1, bool searchadult = false}) async {
    SearchResultModel model;
    String param =
        '/search/multi?api_key=$_apikey&page=$page&include_adult=$searchadult';
    var r = await httpGet(param);
    if (r != null) model = SearchResultModel(r);
    return model;
  }

  ///Get the cast and crew for a movie.
  static Future<CreditsModel> getMovieCredits(int movieid) async {
    CreditsModel model;
    String param =
        '/movie/$movieid/credits?api_key=$_apikey&language=$language';
    var r = await httpGet(param);
    if (r != null) model = CreditsModel(r);
    return model;
  }

  static Future<CreditsModel> getTVCredits(int tvid) async {
    CreditsModel model;
    String param = '/tv/$tvid/credits?api_key=$_apikey&language=$language';
    var r = await httpGet(param);
    if (r != null) model = CreditsModel(r);
    return model;
  }

  ///Get the user reviews for a movie.
  static Future<ReviewModel> getMovieReviews(int movieid,
      {int page = 1}) async {
    ReviewModel model;
    String param = '/movie/$movieid/reviews?api_key=$_apikey&page=$page';
    var r = await httpGet(param);
    if (r != null) model = ReviewModel(r);
    return model;
  }

  static Future<ReviewModel> getTVReviews(int tvid, {int page = 1}) async {
    ReviewModel model;
    String param = '/tv/$tvid/reviews?api_key=$_apikey&page=$page';
    var r = await httpGet(param);
    if (r != null) model = ReviewModel(r);
    return model;
  }

  ///Get the images that belong to a movie.Querying images with a language parameter will filter the results. If you want to include a fallback language (especially useful for backdrops) you can use the include_image_language parameter. This should be a comma seperated value like so: include_image_language=en,null.
  static Future<ImageModel> getMovieImages(int movieid,
      {String includelan = 'en,cn,jp'}) async {
    ImageModel model;
    String param = '/movie/$movieid/images?api_key=$_apikey';
    var r = await httpGet(param);
    if (r != null) model = ImageModel(r);
    return model;
  }

  static Future<ImageModel> getTVImages(int tvid,
      {String includelan = 'en,cn,jp'}) async {
    ImageModel model;
    String param = '/tv/$tvid/images?api_key=$_apikey';
    var r = await httpGet(param);
    if (r != null) model = ImageModel(r);
    return model;
  }

  ///Get the keywords that have been added to a movie.
  static Future<KeyWordModel> getMovieKeyWords(int moiveid) async {
    KeyWordModel model;
    String param = '/movie/$moiveid/keywords?api_key=$_apikey';
    var r = await httpGet(param);
    if (r != null) model = KeyWordModel(r);
    return model;
  }

  static Future<KeyWordModel> getTVKeyWords(int tvid) async {
    KeyWordModel model;
    String param = '/tv/$tvid/keywords?api_key=$_apikey';
    var r = await httpGet(param);
    if (r != null) model = KeyWordModel(r);
    return model;
  }

  ///Discover movies by different types of data like average rating, number of votes, genres and certifications. You can get a valid list of certifications from the certifications list method.Discover also supports a nice list of sort options. See below for all of the available options.Please note, when using certification \ certification.lte you must also specify certification_country. These two parameters work together in order to filter the results. You can only filter results with the countries we have added to our certifications list.If you specify the region parameter, the regional release date will be used instead of the primary release date. The date returned will be the first date based on your query (ie. if a with_release_type is specified). It's important to note the order of the release types that are used. Specifying "2|3" would return the limited theatrical release date as opposed to "3|2" which would return the theatrical date.Also note that a number of filters support being comma (,) or pipe (|) separated. Comma's are treated like an AND and query while pipe's are an OR.
  static Future<VideoListModel> getMovieDiscover(
      {String lan,
      String region,
      String sortBy,
      String certificationCountry,
      String certification,
      String certificationLte,
      bool includeAdult = false,
      bool includeVideo = false,
      int page = 1,
      int primaryReleaseYear,
      String primaryReleaseDateGte,
      String primaryReleaseDateLte,
      String releaseDateGte,
      String releaseDateLte,
      int voteCountGte,
      int voteCountLte,
      double voteAverageGte,
      double voteAverageLte,
      String withCast,
      String withCrew,
      String withCompanies,
      String withGenres,
      String withKeywords,
      String withPeople,
      int year,
      String withoutGenres,
      int withRuntimeGte,
      int withRuntimeLte,
      int withReleaseType,
      String withOriginalLanguage,
      String withoutKeywords}) async {
    VideoListModel model;
    String param =
        '/discover/movie?api_key=$_apikey&page=$page&language=$language';
    param += sortBy == null ? '' : '&sort_by=$sortBy';
    param += certification == null ? '' : '&certification=$certification';
    param += certificationCountry == null
        ? ''
        : '&certification_country=$certificationCountry';
    param +=
        certificationLte == null ? '' : '&certification.lte=$certificationLte';
    param += includeAdult == null ? '' : '&include_adult=$includeAdult';
    param += includeVideo == null ? '' : '&include_video=$includeVideo';
    param += primaryReleaseYear == null
        ? ''
        : '&primary_release_year=$primaryReleaseYear';
    param += primaryReleaseDateGte == null
        ? ''
        : '&primary_release_date.gte=$primaryReleaseDateGte';
    param += primaryReleaseDateLte == null
        ? ''
        : '&primary_release_date.lte=$primaryReleaseDateLte';
    param += releaseDateGte == null ? '' : '&release_date.gte=$releaseDateGte';
    param += releaseDateLte == null ? '' : '&release_date.lte=$releaseDateLte';
    param += voteAverageGte == null ? '' : '&vote_average.gte=$voteAverageGte';
    param += voteCountGte == null ? '' : '&vote_count.gte=$voteCountGte';
    param += voteCountLte == null ? '' : '&vote_count.lte=$voteCountLte';
    param += voteAverageLte == null ? '' : '&vote_average.lte=$voteAverageLte';
    param += withCast == null ? '' : '&with_cast=$withCast';
    param += withCrew == null ? '' : '&with_crew=$withCrew';
    param += withCompanies == null ? '' : '&with_companies=$withCompanies';
    param += withGenres == null ? '' : '&with_genres=$withGenres';
    param += withKeywords == null ? '' : '&with_keywords=$withKeywords';
    param += withPeople == null ? '' : '&with_people=$withPeople';
    param += year == null ? '' : '&year=$year';
    param += withoutGenres == null ? '' : '&without_genres=$withoutGenres';
    param += withRuntimeGte == null ? '' : '&with_runtime.gte=$withRuntimeGte';
    param += withRuntimeLte == null ? '' : '&with_runtime.lte=$withRuntimeLte';
    param +=
        withReleaseType == null ? '' : '&with_release_type=$withReleaseType';
    param += withOriginalLanguage == null
        ? ''
        : '&with_original_language=$withOriginalLanguage';
    param +=
        withoutKeywords == null ? '' : '&without_keywords=$withoutKeywords';
    var r = await httpGet(param);
    if (r != null) model = VideoListModel(r);
    return model;
  }

  static Future<VideoListModel> getTVDiscover(
      {String lan,
      int page,
      String sortBy,
      String airDateGte,
      String airDateLte,
      String firstAirDateGte,
      String firstAirDateLte,
      String timezone = 'America/New_York',
      String withGenres,
      String withKeywords}) async {
    VideoListModel model;
    String param =
        '/discover/tv?api_key=$_apikey&page=$page&timezone=$timezone&language=$language';
    param += sortBy == null ? '' : '&sort_by=$sortBy';
    param += airDateGte == null ? '' : '&air_ate.gte=$airDateGte';
    param += airDateLte == null ? '' : '&air_ate.lte=$airDateLte';
    param +=
        firstAirDateGte == null ? '' : '&first_air_ate.gte=$firstAirDateGte';
    param +=
        firstAirDateLte == null ? '' : '&first_air_ate.lte=$firstAirDateLte';
    param += withGenres == null ? '' : '&with_genres=$withGenres';
    param += withKeywords == null ? '' : '&with_keywords=$withKeywords';
    var r = await httpGet(param);
    if (r != null) model = VideoListModel(r);
    return model;
  }

  ///Search for movies.
  static Future<VideoListModel> searchMovie(String keyword,
      {String lan,
      int page = 1,
      bool includeAdult = false,
      String region,
      int year,
      int primaryReleaseYear}) async {
    VideoListModel model;
    String param =
        '/search/movie?api_key=$_apikey&page=$page&include_adult=$includeAdult';
    param += region == null ? '' : '&region=$region';
    param += year == null ? '' : '&year=$year';
    param += primaryReleaseYear == null
        ? ''
        : '&primary_release_year=$primaryReleaseYear';
    var r = httpGet(param);
    if (r != null) model = VideoListModel(r);
    return model;
  }

  static Future<PeopleDetailModel> getPeopleDetail(int peopleid) async {
    PeopleDetailModel model;
    String param = '/person/$peopleid?api_key=$_apikey&language=$language';
    var r = await httpGet(param);
    if (r != null) model = PeopleDetailModel(r);
    return model;
  }

  static Future<CreditsModel> getPeopleMovieCredits(int peopleid) async {
    CreditsModel model;
    String param =
        '/person/$peopleid/movie_credits?api_key=$_apikey&language=$language';
    var r = await httpGet(param);
    if (r != null) model = CreditsModel(r);
    return model;
  }

  static Future<CombinedCreditsModel> getCombinedCredits(int peopleid) async {
    CombinedCreditsModel model;
    String param =
        '/person/$peopleid/combined_credits?api_key=$_apikey&language=$language';
    var r = await httpGet(param);
    if (r != null) model = CombinedCreditsModel(r);
    return model;
  }

  static Future<String> httpGet(String param) async {
    try {
      if (_appDocPath == null) {
        await getCookieDir();
      }
      var dio = new Dio();
      dio.options.cookies = _cj.loadForRequest(Uri.parse(_apihost));
      var response = await dio.get(_apihost + param);
      var _content = json.encode(response.data);
      return _content;
    } on DioError catch (e) {
      return null;
    }
  }

  static Future<String> httpPost(String params, FormData formData) async {
    try {
      if (_appDocPath == null) {
        await getCookieDir();
      }
      var dio = new Dio();
      dio.options.cookies = _cj.loadForRequest(Uri.parse(_apihost));
      var response = await dio.post(_apihost + params + '?api_key=' + _apikey,
          data: formData);
      var _content = json.encode(response.data);
      return _content;
    } on DioError catch (e) {
      return null;
    }
  }

  static Future<String> httpDelete(String params, FormData formData) async {
    try {
      var dio = new Dio();
      //dio.options.cookies = _cj.loadForRequest(Uri.parse(_apihost));
      var response = await dio.delete(_apihost + params + '?api_key=' + _apikey,
          queryParameters: formData);
      var _content = json.encode(response.data);
      return _content;
    } on DioError catch (e) {
      return null;
    }
  }
}
