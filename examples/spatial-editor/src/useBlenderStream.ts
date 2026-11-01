import {useEffect,useRef,useState} from 'react';
import {BlenderStream,type StreamTelemetry} from './BlenderStream.js';
import type {SpatialCredentials,SpatialMessage} from './SpatialSocket.js';
export function useBlenderStream(credentials:()=>Promise<SpatialCredentials>,onState?:(message:SpatialMessage)=>void){
  const videoRef=useRef<HTMLVideoElement>(null),streamRef=useRef<BlenderStream|null>(null);
  const [telemetry,setTelemetry]=useState<StreamTelemetry>({connection:'idle'});
  useEffect(()=>{if(!videoRef.current)return;const stream=new BlenderStream(videoRef.current,credentials,setTelemetry,onState);streamRef.current=stream;void stream.start();return()=>{stream.close();streamRef.current=null;};},[credentials,onState]);
  return {videoRef,streamRef,telemetry};
}
