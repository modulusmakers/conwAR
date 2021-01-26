//
//  ViewController.swift
//  conwAR
//
//  Created by Brandon Duderstadt on 12/31/20.
//

import UIKit
import ARKit
import AudioToolbox

var keepAliveVals: [Int] = [2, 3]
var bringAliveVals: [Int] = [5]


//Because aparently swift doesnt have mod built in
infix operator %%

extension Int {
    static  func %% (_ left: Int, _ right: Int) -> Int {
        if left >= 0 { return left % right }
        if left >= -right { return (left+right) }
        return ((left % right)+right)%right
    }
}

class ViewController: UIViewController {


    @IBOutlet weak var arView: ARSCNView!
    let arConfig = ARWorldTrackingConfiguration()
    let maxDepth = 5
    var voxelTable: [SIMD3<Int>:SCNNode] = [:]
    var universe: SCNNode = SCNNode(geometry: nil)
    var universeOriginalL: Float = 0.1
    var focusedVoxel: SCNNode? = nil
    var universeStarted: Bool = false
    var focusPointZDist: Float = 0.3
    var focusedVoxelWasAlive: Bool = false

    
    override func viewDidLoad() {
        super.viewDidLoad()
        arView.session.run(arConfig)
    }
    

    @IBAction func toggleFocusedVoxel(_ sender: UITapGestureRecognizer) {
        if universe.geometry == nil || universeStarted{
            return
        }
        AudioServicesPlayAlertSound(1519)
        focusedVoxelWasAlive = !focusedVoxelWasAlive
    }
    
    @IBAction func resizeUniverse(_ sender: UIPinchGestureRecognizer) {
        if sender.state == .changed && universe.geometry != nil {
            let scale_coef = Float(sender.scale)
            universe.scale = SCNVector3(scale_coef*universe.scale.x,
                                        scale_coef*universe.scale.y,
                                        scale_coef*universe.scale.z)
            sender.scale = 1
        }
    }
    
    func updateFocusedVoxel() {
        //There are no voxels to focus on if the universe has not been placed
        //Additionally, if the universe is running, we dont want to interfere with focus
        if universe.geometry == nil || universeStarted{
            return
        }
        
        //Get point just in front of the camera
        var translationMatrix = matrix_identity_float4x4
        translationMatrix.columns.3.z = -1.0 * focusPointZDist
        let focusTransform = matrix_multiply((arView.session.currentFrame?.camera.transform)!,                                    translationMatrix)
        //Search octree to find closest voxel
        var parent = universe
        while parent.childNodes.count > 0 {
            var minChild: SCNNode? = nil
            var minDist:Float? = nil
            for child in parent.childNodes{
                let childTransform = child.worldTransform
                let dist = sqrt(pow(childTransform.m41 - focusTransform.columns.3.x, 2) +
                                pow(childTransform.m42 - focusTransform.columns.3.y, 2) +
                                pow(childTransform.m43 - focusTransform.columns.3.z, 2))
                if minDist == nil || dist < minDist!{
                    minDist = dist
                    minChild = child
                }
            parent = minChild!
            }
        }
        
        //Update focused voxel if necessary
        if focusedVoxel == nil {
            focusedVoxel = parent
            focusedVoxelWasAlive = focusedVoxel!.geometry?.firstMaterial?.diffuse.contents as! UIColor == UIColor.orange
        } else if focusedVoxel != parent {
            if focusedVoxelWasAlive {
                focusedVoxel!.geometry?.firstMaterial?.diffuse.contents = UIColor.orange
                focusedVoxel!.opacity = 0.8
            } else {
                focusedVoxel!.geometry?.firstMaterial?.diffuse.contents = UIColor.clear
                focusedVoxel!.opacity = 0.0
            }
            focusedVoxel = parent
            focusedVoxelWasAlive = focusedVoxel!.geometry?.firstMaterial?.diffuse.contents as! UIColor == UIColor.orange
        } else {}
        focusedVoxel!.geometry?.firstMaterial?.diffuse.contents = UIColor.blue
        focusedVoxel!.opacity = 0.5
    }
    
    @IBAction func placeUniverse(_ sender: UILongPressGestureRecognizer) {

        //Gesture begin case
        if universe.geometry == nil && sender.state == .began{
            
            universe.geometry = SCNBox(width: CGFloat(universeOriginalL),
                                       height: CGFloat(universeOriginalL),
                                       length: CGFloat(universeOriginalL),
                                       chamferRadius: 0)
            universe.geometry?.firstMaterial?.diffuse.contents = UIColor.clear
            universe.opacity = 1.0
            
            var translationMatrix = matrix_identity_float4x4
            translationMatrix.columns.3.z = -0.3
            
            universe.simdTransform = matrix_multiply((arView.session.currentFrame?.camera.transform)!,                                 translationMatrix)

            arView.scene.rootNode.addChildNode(universe)
            
            //TODO fix this abomination
            //because aparently pow(2, parentN) isnt typesafe
            var parentN = 1
            for _ in 0...(maxDepth-1) {
                parentN = 2*parentN
            }

            fillUniverse(parent: universe,
                         parentL: universeOriginalL,
                         parentN: parentN,
                         curDepth: 0,
                         maxDepth: maxDepth,
                         originOffset: [0, 0, 0])
            print("Successfully placed universe!")
            
            initGlider_23_5(i:4, j:4, k:4)
            //run()

            
            //TODO we can deal with voxel focus later
            
            let gdq = DispatchQueue(label: "com.conwAR.queue", qos: .userInteractive)
            gdq.async{
                while !self.universeStarted{
                    usleep(10*1000)
                    self.updateFocusedVoxel()
                }
            }
        } else if sender.state == .began {
            run()
        }
        else {}
    }
    
    func run() {
        //TODO fix this abomination
        //because aparently pow(2, parentN) isnt typesafe
        universeStarted = true
        var totalN = 1
        for _ in 0...(maxDepth-1) {
            totalN = 2*totalN
        }
        
        let gdq = DispatchQueue(label: "com.conwAR.queue", qos: .userInteractive)
        gdq.async{
            //Populate initial list of living cells
            var allAlive: Set<SIMD3<Int>> = []
            for i in 0...(totalN-1) {
                for j in 0...(totalN-1) {
                    for k in 0...(totalN-1) {
                        let alive = self.getVoxel(i:i, j:j, k:k)!.geometry?.firstMaterial?.diffuse.contents as! UIColor != UIColor.clear
                        if alive{
                            allAlive.insert(SIMD3<Int>([i, j, k]))
                        }
                    }
                }
            }
            
            //Continuously update living cells
            while true {
                //Compute updates
                var toCheck: Set<SIMD3<Int>> = allAlive
                var toBringAlive: [SIMD3<Int>] = []
                var toKill: [SIMD3<Int>] = []
                for cellCoords in allAlive {
                    let i = cellCoords.x
                    let j = cellCoords.y
                    let k = cellCoords.z
                    for di in -1...1 {
                        for dj in -1...1 {
                            for dk in -1...1{
                                if abs(di) + abs(dj) + abs(dk) != 0{
                                    toCheck.insert(SIMD3<Int>([(i+di)%%totalN,
                                                               (j+dj)%%totalN,
                                                               (k+dk)%%totalN]))
                                }
                            }
                        }
                    }
                }
                
                for cellCoords in toCheck{
                    let i = cellCoords.x
                    let j = cellCoords.y
                    let k = cellCoords.z
                    let alive = self.getVoxel(i:i, j:j, k:k)!.geometry?.firstMaterial?.diffuse.contents as! UIColor != UIColor.clear
                    let livingNeighbors = self.countLivingNeighbors(i: i,
                                                                    j: j,
                                                                    k: k,
                                                                    totalN: totalN)
                    if alive && !keepAliveVals.contains(livingNeighbors) {
                        toKill.append(SIMD3<Int>([i, j, k]))
                    }
                    if !alive && bringAliveVals.contains(livingNeighbors) {
                        toBringAlive.append(SIMD3<Int>([i, j, k]))
                    }
                }
                
                //Execute updates
                for voxelCoords in toBringAlive {
                    self.setVoxel(i: voxelCoords.x, j: voxelCoords.y, k: voxelCoords.z)
                    allAlive.insert(SIMD3<Int>([voxelCoords.x, voxelCoords.y, voxelCoords.z]))
                }
                for voxelCoords in toKill {
                    self.unsetVoxel(i: voxelCoords.x, j: voxelCoords.y, k: voxelCoords.z)
                    allAlive.remove(SIMD3<Int>([voxelCoords.x, voxelCoords.y, voxelCoords.z]))
                }
                //TODO Wait before progressing to next frame
            }
        }
    }
    
    func countLivingNeighbors(i: Int, j: Int, k: Int, totalN: Int) -> Int {
        var aliveCount: Int = 0
        for di in -1...1 {
            for dj in -1...1 {
                for dk in -1...1{
                    //Dont count center voxel and dont do corners
                    if abs(di) + abs(dj) + abs(dk) != 0{
                        let voxel = self.getVoxel(i: (i+di)%%totalN,
                                                  j: (j+dj)%%totalN,
                                                  k: (k+dk)%%totalN)
                        let alive = voxel!.geometry?.firstMaterial?.diffuse.contents as! UIColor != UIColor.clear
                        if alive {
                            aliveCount = aliveCount + 1
                        }
                    }
                }
            }
        }
        return aliveCount
    }
    
    func getVoxel(i: Int, j: Int, k: Int) -> SCNNode? {
        let key = SIMD3<Int>([i, j, k])
        return voxelTable[key]
    }
    
    func getVoxelTest() {
        //TODO fix this abomination
        //because aparently pow(2, parentN) isnt typesafe
        var totalN = 1
        for _ in 0...(maxDepth-1) {
            totalN = 2*totalN
        }
        
        let gdq = DispatchQueue(label: "com.conwAR.queue", qos: .userInteractive)
        gdq.async{
            while true {
                for i in 0...(totalN-1) {
                    for j in 0...(totalN-1) {
                        for k in 0...(totalN-1) {
                            var voxel = self.getVoxel(i:i, j:j, k:k)
                            voxel!.geometry?.firstMaterial?.diffuse.contents = UIColor.orange
                            voxel!.opacity = 0.8
                            usleep(100 * 1000)
                            voxel!.geometry?.firstMaterial?.diffuse.contents = UIColor.clear
                            voxel!.opacity = 0.0
                        }
                    }
                }
            }
        }
    }
    
    func setVoxel(i: Int, j: Int, k: Int) {
        var voxel = self.getVoxel(i:i, j:j, k:k)
        voxel!.geometry?.firstMaterial?.diffuse.contents = UIColor.orange
        voxel!.opacity = 0.8
        
    }
    
    func unsetVoxel(i: Int, j: Int, k: Int) {
        var voxel = self.getVoxel(i:i, j:j, k:k)
        voxel!.geometry?.firstMaterial?.diffuse.contents = UIColor.clear
        voxel!.opacity = 0.0
        
    }
    
    func initGlider_23_5(i: Int, j:Int, k: Int) {
        //i, j, k defines corner
        
        setVoxel(i: i, j: j, k: k)
        setVoxel(i: i+3, j:j, k:k)
        setVoxel(i:i, j:j+3, k:k)
        setVoxel(i:i+3, j:j+3, k:k)
        setVoxel(i:i+1, j:j, k:k+1)
        setVoxel(i:i+2, j:j, k:k+1)
        setVoxel(i: i, j: j+1, k: k+1)
        setVoxel(i:i+3, j:j+1, k: k+1)
        setVoxel(i:i, j:j+2, k:k+1)
        setVoxel(i:i+3, j:j+2, k:k+1)
        setVoxel(i:i+1, j:j+3, k:k+1)
        setVoxel(i:i+2, j:j+3, k:k+1)
        
        
        
    }
    
    func fillUniverse(parent: SCNNode,
                      parentL:Float,
                      parentN: Int,
                      curDepth: Int,
                      maxDepth: Int,
                      originOffset: SIMD3<Int>) {
        let curL = Float(parent.scale.x) * parentL / 2.0
        let curN = parentN / 2
        var curOriginOffset = originOffset
        
        if curDepth < maxDepth{
            for i in 0...7{
                curOriginOffset = originOffset
                
                //Figure out signs for this particular child
                var bitrep = String(i, radix: 2)
                if bitrep.count < 3{
                    for _ in 1...(3-bitrep.count){
                        bitrep = "0" + bitrep
                    }
                }
                let bitarr = Array(bitrep)
                var x_sign = 1
                var y_sign = 1
                var z_sign = 1
                var x_bitint = 0 //look im not thrilled about this either but
                var y_bitint = 0 //adding two vars of slightly differnt types
                var z_bitint = 0 //in Swift brings great pain, so here we are
                if bitarr[0] == "1"{
                    x_sign = x_sign * -1
                    curOriginOffset[0] = curOriginOffset[0] + curN
                    x_bitint = 1
                }
                if bitarr[1] == "1"{
                    y_sign = y_sign * -1
                    curOriginOffset[1] = curOriginOffset[1] + curN
                    y_bitint = 1
                }
                if bitarr[2] == "1"{
                    z_sign = z_sign * -1
                    curOriginOffset[2] = curOriginOffset[2] + curN
                    z_bitint = 1
                }
            
                //Construct child node
                let child: SCNNode = SCNNode(geometry: SCNBox(width: CGFloat(curL),
                                                              height: CGFloat(curL),
                                                              length: CGFloat(curL),
                                                              chamferRadius: 0))
                child.geometry?.firstMaterial?.diffuse.contents = UIColor.clear
                
                //Place child node within parent
                var translationMatrix = matrix_identity_float4x4
                translationMatrix.columns.3.x = Float(x_sign) * curL / 2.0
                translationMatrix.columns.3.y = Float(y_sign) * curL / 2.0
                translationMatrix.columns.3.z = Float(z_sign) * curL / 2.0
                child.simdTransform = translationMatrix
                parent.addChildNode(child)

                //Non leaf case
                if curDepth+1 < maxDepth {
                    fillUniverse(parent: child,
                                 parentL: curL,
                                 parentN: curN,
                                 curDepth: curDepth+1,
                                 maxDepth: maxDepth,
                                 originOffset: curOriginOffset)
                //Leaf case
                } else {
                    //Kool AD: "Life is pain that's beautiful ain't it"
                    let curIdx: SIMD3<Int> = [x_bitint + originOffset[0],
                                              y_bitint + originOffset[1],
                                              z_bitint + originOffset[2]]
                    voxelTable[curIdx] = child
                }
            }
        }
    }
}

class settingsViewController: UIViewController, UITextFieldDelegate {
    
    @IBOutlet weak var keepAliveText: UITextField!
    
    @IBOutlet weak var bringAliveText: UITextField!

    override func viewDidLoad() {
           super.viewDidLoad()
           self.keepAliveText.delegate = self
        
            self.bringAliveText.delegate = self
       }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let accessIdentifier = textField.accessibilityIdentifier!
        let text = textField.text
        let tempArray = text!.split(separator: ",")
        let intArray = tempArray.map { Int($0)! }
        
        if accessIdentifier == "keepAliveIdentifier" {
            keepAliveVals = intArray
        }
        
        if accessIdentifier == "bringAliveIdentifier" {
            bringAliveVals = intArray
        }
        self.view.endEditing(true)
        return false
    }
    
}
