#Requires AutoHotkey v2.0
#SingleInstance Force
#Include JKUtility.ahk

; 이벤트 enum
class EventType
{
    static SUBMIT => 0
}

; wmp 와 같은 파일에 등급 매기기 기능
class JKWinShellRating
{
    ; MARK: 변수 영역
    /**
     * #### 등급 값 파일탐색기 스타일 매핑
     * @type {Map<Number, Number>} 
     */
    static RATING_MAP := Map(
        0, 0,
        1, 1,
        2, 25,
        3, 50,
        4, 75,
        5, 99
    )

    /**
     * #### 메인 gui
     * @type {Gui} 
     */
    static gui := 0

    /**
     * #### 이벤트 타입과 처리 함수 바인딩 맵
     * @type {Map<EventType, BoundFunc>} 
     */
    static eventMap := Map(
        EventType.SUBMIT, this.Submit.Bind(this)
    )

    ; MARK: 함수 영역

    /**
     * #### 시작 함수
     * @description gui 생성 및 딜리게이트 바인딩
     * @returns {void} - 
     */
    static BeginPlay()
    {
        this.gui := RatingGUI(this.EventDispatcher.Bind(this))
    }

    /**
     * #### 파일에 등급 매기기
     * @param {String} fullPath - 파일 전체 경로
     * @param {Number} stars - 등급 점수
     * @returns {Bool} - 성공 여부
     */
    static SetRating(fullPath, stars)
    {
        ratingValue := this.RATING_MAP.Has(stars) ? this.RATING_MAP[stars] : 0

        ; PKEY_Rating 구조체 생성 (GUID + PID 9)
        propKey := Buffer(20, 0)
        DllCall("ole32\CLSIDFromString"
        , "Str", "{64440492-4C8B-11D1-8B70-080036B11A03}"
        , "Ptr", propKey.Ptr
        , "HRESULT")
        NumPut("UInt", 9, propKey, 16)

        ; IPropertyStore 인터페이스 GUID 구조체 생성
        riid := Buffer(16, 0)
        DllCall("ole32\CLSIDFromString"
        , "Str", "{886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99}"
        , "Ptr", riid.Ptr
        , "HRESULT")

        ; PROPVARIANT 구조체 생성
        propVar := Buffer(16, 0)
        NumPut("UShort", JKEnum.VARTYPE.UI4, propVar, 0)
        NumPut("UInt", ratingValue, propVar, 8)

        pStore := 0
        
        hr := DllCall("shell32\SHGetPropertyStoreFromParsingName"
        , "Str", fullPath
        , "Ptr", 0
        , "UInt", JKEnum.GETPROPERTYSTOREFLAGS.READWRITE
        , "Ptr", riid.Ptr
        , "Ptr*", &pStore
        , "HRESULT")
        
        if (hr != 0 || !pStore)
            return false

        ComCall(JKEnum.IPropertyStore.SetValue, pStore, "Ptr", propKey.Ptr, "Ptr", propVar.Ptr)

        ComCall(JKEnum.IPropertyStore.Commit, pStore)

        ComCall(JKEnum.IUnknown.Release, pStore)

        return true
    }

    /**
     * #### gui 이벤트 분리 처리
     * @param {EventType} eventType - 이벤트 종류 enum
     * @param {Any[]} params - 이벤트에 따른 매개변수들
     * @returns {void} - 
     */                 
    static EventDispatcher(eventType, params*)
    {
        if(this.eventMap.Has(eventType))
            this.eventMap[eventType](params*)
    }

    /**
     * #### 입력 제출 이벤트
     * @param {String} fullPath - 파일 전체 경로
     * @param {Number} selectIdx - 등급 idx
     * @param {Any[]} * - 안쓰는 매개변수
     * @returns {void} - 
     */
    static Submit(fullPath, selectIdx)
    {
        ; @@ 처리가 오래걸려서 응답없음 나올 수 있는데, 그러지 않게 비동기 처리하기
        if (!fullPath || !FileExist(fullPath))
        {
            JKUtility.JKTooltip("파일을 먼저 선택해주세요.", 1500)
            return
        }

        stars := selectIdx - 1

        success := this.SetRating(fullPath, stars)
        if (success)
            JKUtility.JKTooltip("등급이 성공적으로 반영되었습니다!", 1500)
        else
            JKUtility.JKTooltip("등급 설정에 실패했습니다.", 1500)
    }
}

class RatingGUI
{
    /**
     * #### 이벤트 딜리게이트
     * @type {Array<BoundFunc>} 
     */
    eventDel := []

    /**
     * #### 생성자
     * @param {BoundFunc} eventCallback - 이벤트 반환용 바인딩 함수
     * @returns {void} - 
     */
    __New(eventCallback := 0)
    {
        this.gui := Gui(, "JKWinShellRating")
        this.gui.SetFont("s10", "Segoe UI")

        this.gui.Add("Text", "w300", "대상 파일:")
        this.editFile := this.gui.Add("Edit", "w230 vFilePath")
        this.btnBrowse := this.gui.Add("Button", "x+5 w75", "찾아보기...")
        this.btnBrowse.OnEvent("Click", (*) => this.OnBrowseClick())

        this.gui.Add("Text", "y+15 w300", "별점 선택 (0 ~ 5):")
        this.ddlRating := this.gui.Add("DropDownList", "w300 Choose6", ["0점 (없음)", "1점 (★)", "2점 (★★)", "3점 (★★★)", "4점 (★★★★)", "5점 (★★★★★)"])

        this.btnSubmit := this.gui.Add("Button", "y+20 w300 Default", "적용하기")
        this.btnSubmit.OnEvent("Click", (*) => this.OnSubmitClick())

        ; 이벤트 콜백 주입
        if(eventCallback)
            this.eventDel.Push(eventCallback)

        this.gui.Show()
    }

    /**
     * #### 파일 선택 이벤트
     * @returns {void} - 
     */
    OnBrowseClick()
    {
        selectFile := FileSelect(3, , "미디어 파일 선택", "Media Files (*.mp4; *.mp3; *.mkv; *.wma)")
        if (selectFile)
            this.editFile.Value := selectFile
    }

    /**
     * #### 입력 제출 이벤트
     * @returns {void} 
     */
    OnSubmitClick()
    {
        filePath := Trim(this.editFile.Value, '"')
        selectIdx := this.ddlRating.Value

        ; submit 이벤트 처리
        JKUtility.CallMulticastDel(this.eventDel, EventType.SUBMIT, filePath, selectIdx)
    }
}

; MARK: 실행 영역

JKWinShellRating.BeginPlay()