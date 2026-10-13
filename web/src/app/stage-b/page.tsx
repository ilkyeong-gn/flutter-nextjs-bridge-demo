export default function StageBPage() {
  return (
    <div className="bg-white rounded-xl p-6 shadow-sm border border-gray-200">
      <h2 className="text-xl font-bold text-gray-900 mb-2">Stage B: 양방향 이벤트 (Host → Web)</h2>
      <p className="text-gray-600 mb-6 text-sm">
        Host에서 발생한 상태 변경 이벤트를 Web이 수신하여 화면에 반영하는 양방향 통신입니다.
      </p>
      <div className="bg-gray-50 border border-dashed border-gray-300 rounded-lg p-6 text-center text-gray-500">
        Stage B 구현 준비 완료 (대기 중: Issue #9)
      </div>
    </div>
  );
}
